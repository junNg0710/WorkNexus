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
        XCTAssertTrue(s.petShowsDetails, "it says what a message or notification says unless told not to")
        var chosen = AppSettings()
        chosen.petId = "fox"; chosen.petDisplay = .floating; chosen.petFollowsCursor = false; chosen.petShowsDetails = false
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(chosen))
        XCTAssertEqual(back.petId, "fox"); XCTAssertEqual(back.petDisplay, .floating); XCTAssertFalse(back.petFollowsCursor)
        XCTAssertFalse(back.petShowsDetails)
        // An unknown display (a newer build) falls back rather than losing the settings.
        let odd = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"petDisplay": "orbit", "showPet": false}"#.utf8))
        XCTAssertEqual(odd.petDisplay, .inWindow); XCTAssertFalse(odd.showPet)
    }

    func testThePetSaysWhatAChatMessageSays() {
        XCTAssertEqual(PetSignalText.chat(PetChatNews(title: "Lan", sender: nil, body: "ok em", number: 1)), "Lan: ok em")
        XCTAssertEqual(PetSignalText.chat(PetChatNews(title: "Team", sender: "Lan", body: "Photo", number: 2)), "Team · Lan: Photo")
        XCTAssertEqual(PetSignalText.chat(PetChatNews(title: "", sender: nil, body: "hi", number: 3)), "hi")
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

    func testTheFloatingPetStrollsAlongAStripAroundWhereItWasPut() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let span = FloatingPetPanel.strollSpan
        // In the middle: the strip is centred on its place, which is halfway along.
        let mid = FloatingPetPanel.strip(home: 700, petWidth: 96, span: span, screen: screen)
        XCTAssertEqual(mid.travel, span - 96)
        XCTAssertEqual(mid.start + mid.travel / 2, 700)
        // Near the right edge: the strip stops at the edge, so the pet strolls to its left.
        let edge = FloatingPetPanel.strip(home: 1480, petWidth: 96, span: span, screen: screen)
        XCTAssertEqual(edge.start + edge.travel + 48, 1512)
        XCTAssertGreaterThan((1480 - edge.start) / edge.travel, 0.5)
    }

    func testOverTheAppsWindowTheFloatingPetStrollsItsWholeWidth() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 950), window = CGRect(x: 100, y: 50, width: 1200, height: 800)
        let over = FloatingPetPanel.strip(home: 700, petWidth: 96, span: FloatingPetPanel.strollSpan, screen: screen, window: window)
        XCTAssertEqual(over.start, 100 + 48); XCTAssertEqual(over.travel, 1200 - 96)
        // A window partly off the screen: only the part on it.
        let off = FloatingPetPanel.strip(home: 1400, petWidth: 96, span: 360, screen: screen, window: CGRect(x: 1000, y: 0, width: 900, height: 600))
        XCTAssertEqual(off.start + off.travel + 48, 1512)
        // Away from the window: the strip around its place.
        let away = FloatingPetPanel.strip(home: 50, petWidth: 96, span: 360, screen: screen, window: window)
        XCTAssertEqual(away.travel, 360 - 96)
    }

    func testAFloatingWalkGoesFromWhereThePetStands() {
        let start = Date(timeIntervalSince1970: 0)
        let walk = PetDirector.Walk(from: 0.2, to: 0.8, start: start, duration: 2)
        XCTAssertEqual(FloatingPetPanel.progress(walk, at: start), 0)
        XCTAssertEqual(FloatingPetPanel.progress(walk, at: start.addingTimeInterval(1)), 0.5, accuracy: 0.001)
        XCTAssertEqual(FloatingPetPanel.progress(walk, at: start.addingTimeInterval(3)), 1)
    }

    func testTheFloatingPetStaysOnAScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        let size = CGSize(width: 96, height: 104)
        XCTAssertEqual(FloatingPetPanel.onScreen(origin: NSPoint(x: 2000, y: 500), size: size, screens: screens), NSPoint(x: 2000, y: 500))
        // Its screen is gone (unplugged): onto the nearest one, just inside its edge.
        XCTAssertEqual(FloatingPetPanel.onScreen(origin: NSPoint(x: 5000, y: 500), size: size, screens: screens), NSPoint(x: 3360 - 96, y: 500))
        XCTAssertEqual(FloatingPetPanel.onScreen(origin: nil, size: size, screens: screens), NSPoint(x: 1320, y: 24))
        // Half of it under the Dock (the visible frame starts above it): lifted fully above.
        let withDock = [CGRect(x: 0, y: 80, width: 1440, height: 790)]
        XCTAssertEqual(FloatingPetPanel.onScreen(origin: NSPoint(x: 600, y: 30), size: size, screens: withDock), NSPoint(x: 600, y: 80))
        // Past the right edge of a smaller screen: pulled back inside.
        XCTAssertEqual(FloatingPetPanel.onScreen(origin: NSPoint(x: 1400, y: 300), size: size, screens: [screens[0]]), NSPoint(x: 1440 - 96, y: 300))
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
