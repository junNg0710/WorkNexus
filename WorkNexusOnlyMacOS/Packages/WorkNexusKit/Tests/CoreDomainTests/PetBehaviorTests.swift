import XCTest
@testable import CoreDomain

final class PetBehaviorTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }

    func testItComesAsThePetAlwaysBehaved() {
        let b = PetBehavior()
        XCTAssertEqual(b.activity, .normal); XCTAssertEqual(b.activity.pause, 8...20); XCTAssertTrue(b.activity.wanders)
        XCTAssertTrue(b.idleGestures); XCTAssertEqual(b.roam, .nearby); XCTAssertTrue(b.ignored.isEmpty)
        XCTAssertTrue(b.speaks); XCTAssertEqual(b.speechLength, .normal); XCTAssertTrue(b.statusOnHover); XCTAssertNil(b.quietUntil)
        for event in PetEvent.allCases { XCTAssertTrue(PetReacts(b).to(event), "\(event)") }
    }

    func testSettingsSavedBeforeItGetIt() throws {
        let old: AppSettings = try decode("{\"showPet\": true}")
        XCTAssertEqual(old.petBehavior, PetBehavior())
        // A value this build does not know (a later one's) falls back, the rest is kept.
        let partial: PetBehavior = try decode("{\"activity\": \"frantic\", \"speaks\": false, \"ignored\": [\"sync\"]}")
        XCTAssertEqual(partial.activity, .normal); XCTAssertFalse(partial.speaks); XCTAssertEqual(partial.ignored, [.sync])
    }

    func testItIsKept() throws {
        var s = AppSettings()
        s.petBehavior.activity = .lively; s.petBehavior.roam = .screen; s.petBehavior.ignored = [.chat, .apps]
        s.petBehavior.speechLength = .long; s.petBehavior.idleGestures = false; s.petBehavior.statusOnHover = false
        s.petBehavior.quietUntil = Date(timeIntervalSince1970: 2_000_000)
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.petBehavior, s.petBehavior)
    }

    func testTheLivelierTheSoonerItMoves() {
        XCTAssertLessThan(PetActivity.lively.pause.upperBound, PetActivity.normal.pause.upperBound)
        XCTAssertGreaterThan(PetActivity.calm.pause.lowerBound, PetActivity.normal.pause.upperBound)
        XCTAssertFalse(PetActivity.still.wanders)
    }

    func testStandStillAndBackToHowItMoved() {
        var b = PetBehavior()
        b.activity = .lively
        b.toggleStandingStill()
        XCTAssertEqual(b.activity, .still)
        b.toggleStandingStill()
        XCTAssertEqual(b.activity, .lively); XCTAssertNil(b.resumeActivity)
        // Set to stand still in the settings: "walk about again" is the usual pace.
        b.activity = .still
        b.toggleStandingStill()
        XCTAssertEqual(b.activity, .normal)
    }

    func testItReactsToWhatIsNotTurnedOff() {
        var b = PetBehavior()
        b.ignored = [.sync, .apps]
        let reacts = PetReacts(b)
        XCTAssertFalse(reacts.to(.sync)); XCTAssertFalse(reacts.to(.apps))
        XCTAssertTrue(reacts.to(.chat)); XCTAssertTrue(reacts.to(.notifications)); XCTAssertTrue(reacts.to(.celebration))
        XCTAssertTrue(reacts.speaks)
        b.speaks = false
        XCTAssertFalse(PetReacts(b).speaks); XCTAssertTrue(PetReacts(b).to(.chat), "it still waves, without a word")
    }

    func testQuietForAWhile() {
        var b = PetBehavior()
        let now = Date(timeIntervalSince1970: 1_000_000)
        b.quietUntil = now.addingTimeInterval(3600)
        let during = PetReacts(b, now: now.addingTimeInterval(1800))
        XCTAssertTrue(during.isQuiet); XCTAssertFalse(during.speaks)
        for event in PetEvent.allCases { XCTAssertFalse(during.to(event), "\(event)") }
        let after = PetReacts(b, now: now.addingTimeInterval(3601))
        XCTAssertFalse(after.isQuiet); XCTAssertTrue(after.speaks); XCTAssertTrue(after.to(.chat))
    }

    func testLinesStayAsLongAsTheUserLikes() {
        var b = PetBehavior()
        XCTAssertEqual(PetReacts(b).seconds(6), 6, accuracy: 1e-9)
        b.speechLength = .short
        XCTAssertEqual(PetReacts(b).seconds(6), 4, accuracy: 1e-9)
        b.speechLength = .long
        XCTAssertEqual(PetReacts(b).seconds(6), 10, accuracy: 1e-9)
    }

    func testResetPutsThePetsSettingsBackAndKeepsThePet() {
        var s = AppSettings()
        s.petId = "fox"; s.showPet = false; s.petDisplay = .inWindow; s.petFollowsCursor = false; s.petShowsDetails = false
        s.petStaysWhenAppHides = false; s.petClickGoesBack = false; s.petScale = 1.7
        s.petBehavior.activity = .still; s.petBehavior.ignored = [.chat]; s.petBehavior.speaks = false
        s.chatTextScale = 1.2
        s.resetPet()
        var fresh = AppSettings()
        fresh.petId = "fox"; fresh.chatTextScale = 1.2
        XCTAssertEqual(s, fresh, "only the pet's settings go back; the pet chosen and everything else stay")
    }
}
