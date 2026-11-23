import XCTest
@testable import CoreDomain

final class RailShortcutsTests: XCTestCase {
    private let places = ["workspace", "chat", "tasks", "bugs", "docs", "g1", "g2", "m1", "m2", "m3", "settings"]
    private func keys(_ code: Int, _ label: String, _ mods: KeyShortcut.Modifiers) -> KeyShortcut { KeyShortcut(keyCode: code, label: label, modifiers: mods) }
    private func cmd(_ n: Int) -> KeyShortcut { KeyShortcut.byPosition(n)! }

    func testShortcutsAreWrittenAsMenusWriteThem() {
        XCTAssertEqual(cmd(1).display, "⌘1")
        XCTAssertEqual(keys(8, "C", [.command, .shift, .control, .option]).display, "⌃⌥⇧⌘C")
        XCTAssertEqual(keys(96, "F5", []).display, "F5")
        // The same keys are the same shortcut whatever the input method printed for them.
        XCTAssertEqual(keys(18, "1", .command), keys(18, "!", .command))
        XCTAssertNotEqual(keys(18, "1", .command), keys(18, "1", [.command, .shift]))
    }

    func testOnlyKeysThatAreSafeToTakeCanBeAShortcut() {
        XCTAssertEqual(keys(11, "B", []).problem, .needsCommandOrControl)
        XCTAssertEqual(keys(11, "B", [.shift, .option]).problem, .needsCommandOrControl)
        XCTAssertNil(keys(11, "B", .command).problem)
        XCTAssertNil(keys(11, "B", .control).problem)
        XCTAssertNil(keys(96, "F5", []).problem, "a function key needs nothing held")
        // The app's menus and text editing keep theirs, with or without ⇧.
        for (code, label) in [(8, "C"), (9, "V"), (40, "K"), (45, "N"), (13, "W"), (12, "Q"), (43, ","), (15, "R")] {
            XCTAssertEqual(keys(code, label, .command).problem, .reserved, label)
        }
        XCTAssertEqual(keys(4, "H", [.command, .shift]).problem, .reserved, "the chat privacy mode")
        XCTAssertNil(keys(8, "C", [.command, .option]).problem)
        XCTAssertNil(keys(8, "C", .control).problem)
    }

    func testThePlacesAnswerToTheKeysOfTheirPosition() {
        let out = ResolveRailShortcuts()(places: places, settings: RailShortcuts())
        XCTAssertEqual(out["workspace"]?.display, "⌘1"); XCTAssertEqual(out["chat"]?.display, "⌘2"); XCTAssertEqual(out["m2"]?.display, "⌘9")
        // The tenth is ⌘0, the next ten take ⌥ as well: the websites and Mac apps added under the accounts have keys too.
        XCTAssertEqual(out["m3"]?.display, "⌘0"); XCTAssertEqual(out["settings"]?.display, "⌥⌘1")
        XCTAssertEqual(out.count, places.count)
        XCTAssertEqual(KeyShortcut.byPosition(20)?.display, "⌥⌘0"); XCTAssertEqual(KeyShortcut.byPosition(10)?.keyCode, 29)
        XCTAssertNil(KeyShortcut.byPosition(21)); XCTAssertNil(KeyShortcut.byPosition(0))
    }

    func testHeldModifiersShowWhatIsLeftToPress() {
        XCTAssertEqual(cmd(3).hint(whileHolding: .command), "3")
        XCTAssertEqual(cmd(12).hint(whileHolding: .command), "⌥2", "⌥ is still to be added")
        XCTAssertEqual(cmd(12).hint(whileHolding: [.command, .option]), "2")
        XCTAssertNil(cmd(3).hint(whileHolding: [.command, .option]), "⌘3 is not made with ⌥")
        XCTAssertNil(cmd(3).hint(whileHolding: .control)); XCTAssertNil(cmd(3).hint(whileHolding: []))
        XCTAssertEqual(keys(38, "J", .control).hint(whileHolding: .control), "J")
    }

    func testAChosenShortcutStaysWithItsPlace() {
        var s = RailShortcuts()
        let chosen = keys(38, "J", [.command, .shift])
        s.assign(chosen, to: "settings", places: places)
        XCTAssertEqual(ResolveRailShortcuts()(places: places, settings: s)["settings"], chosen)
        // The rail changes (an account goes): the place keeps its keys, the others move up with their position.
        let fewer = places.filter { $0 != "g1" }
        let out = ResolveRailShortcuts()(places: fewer, settings: s)
        XCTAssertEqual(out["settings"], chosen); XCTAssertEqual(out["g2"], cmd(6)); XCTAssertEqual(out["m3"], cmd(9))
        XCTAssertEqual(out.count, fewer.count)
    }

    func testOneCombinationNeverOpensTwoPlaces() {
        var s = RailShortcuts()
        // Chat takes the dashboard's ⌘1: the dashboard is left without, and does not take another place's.
        s.assign(cmd(1), to: "chat", places: places)
        var out = ResolveRailShortcuts()(places: places, settings: s)
        XCTAssertEqual(out["chat"], cmd(1)); XCTAssertNil(out["workspace"]); XCTAssertEqual(out["tasks"], cmd(3))
        XCTAssertEqual(Set(out.values).count, out.count)
        // A chosen combination moves to the place it is given to next.
        let chosen = keys(38, "J", .control)
        s.assign(chosen, to: "bugs", places: places); s.assign(chosen, to: "docs", places: places)
        out = ResolveRailShortcuts()(places: places, settings: s)
        XCTAssertEqual(out["docs"], chosen); XCTAssertNil(out["bugs"])
    }

    func testARemovedShortcutStaysRemovedUntilReset() {
        var s = RailShortcuts()
        s.assign(nil, to: "chat", places: places)
        XCTAssertNil(ResolveRailShortcuts()(places: places, settings: s)["chat"])
        XCTAssertEqual(ResolveRailShortcuts()(places: places, settings: s)["tasks"], cmd(3), "the others keep their number")
        s.assign(cmd(2), to: "chat", places: places)
        XCTAssertEqual(ResolveRailShortcuts()(places: places, settings: s)["chat"], cmd(2))
        s = RailShortcuts()
        XCTAssertEqual(ResolveRailShortcuts()(places: places, settings: s)["chat"], cmd(2))
    }

    func testSwitchedOffNothingOpensAPlace() {
        var s = RailShortcuts()
        s.enabled = false
        XCTAssertTrue(ResolveRailShortcuts()(places: places, settings: s).isEmpty)
        // Choosing keys while off still takes them from the place that had them.
        s.assign(cmd(1), to: "chat", places: places)
        s.enabled = true
        let out = ResolveRailShortcuts()(places: places, settings: s)
        XCTAssertEqual(out["chat"], cmd(1)); XCTAssertNil(out["workspace"])
    }

    func testTheChoicesAreKeptAndOlderSettingsStillLoad() throws {
        var s = AppSettings()
        s.railShortcuts.assign(keys(38, "J", [.command, .option]), to: "chat", places: places)
        s.railShortcuts.assign(nil, to: "docs", places: places)
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.railShortcuts, s.railShortcuts)
        XCTAssertEqual(back.railShortcuts.custom["chat"]?.label, "J")
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{\"showPet\": true}".utf8))
        XCTAssertEqual(old.railShortcuts, RailShortcuts())
        let partial = try JSONDecoder().decode(RailShortcuts.self, from: Data("{\"enabled\": false, \"custom\": 3}".utf8))
        XCTAssertFalse(partial.enabled); XCTAssertTrue(partial.custom.isEmpty)
    }
}
