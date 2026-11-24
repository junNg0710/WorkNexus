import CoreDomain
import XCTest
@testable import FeatureMiniApps

/// The fold of the bars over a mini app's page: what the button says and asks for, and that the choice is kept.
@MainActor
final class MiniAppBarsTests: XCTestCase {
    func testTheButtonAsksForTheOtherStateAndNothingWhenItIsAlreadyThere() {
        var asked: [Bool] = []
        let open = MiniAppBars(collapsed: false) { asked.append($0) }
        open.set(false); XCTAssertEqual(asked, [], "the bars are open already")
        open.set(true); XCTAssertEqual(asked, [true])
        let folded = MiniAppBars(collapsed: true) { asked.append($0) }
        folded.set(true); XCTAssertEqual(asked, [true])
        folded.set(false); XCTAssertEqual(asked, [true, false])
    }

    func testTheButtonShowsWhichWayTheBarsGo() {
        let open = MiniAppBars(collapsed: false), folded = MiniAppBars(collapsed: true)
        XCTAssertEqual(open.turn.degrees, 0); XCTAssertEqual(folded.turn.degrees, 180, "the arrow turns over to point down")
        XCTAssertNotEqual(open.help, folded.help)
    }

    func testWithoutAnAppToKeepItTheBarsAreOpen() {
        XCTAssertFalse(MiniAppBars().collapsed)
        MiniAppBars().set(true)   // nothing to tell: no crash
    }

    func testTheChoiceIsKeptInTheSettingsAndOlderSettingsOpenTheBars() throws {
        var s = AppSettings()
        XCTAssertFalse(s.miniAppBarsCollapsed)
        s.miniAppBarsCollapsed = true
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)).miniAppBarsCollapsed)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data("{\"showPet\": true}".utf8)).miniAppBarsCollapsed)
    }
}
