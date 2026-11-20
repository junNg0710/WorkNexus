import AppKit
import XCTest
@testable import CoreUI

@MainActor
final class AppNativeMenuTests: XCTestCase {
    /// The message "…" menu: every action, groups split by a line, the destructive one in red, and a pick runs its action.
    func testItemsBecomeAMenuWhosePicksRunTheirActions() throws {
        var ran: [String] = []
        let menu = AppNativeMenu.menu([
            .init("Copy text", icon: "doc.on.doc") { ran.append("copy") },
            .init("Create bug", icon: "ladybug", dividerBefore: true) { ran.append("bug") },
            .init("Retract", icon: "arrow.uturn.backward", destructive: true, dividerBefore: true) { ran.append("retract") },
        ])
        XCTAssertEqual(menu.items.map(\.isSeparatorItem), [false, true, false, true, false])
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.map(\.title), ["Copy text", "Create bug", "Retract"])
        XCTAssertTrue(menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.isEnabled && $0.image != nil })
        let retract = try XCTUnwrap(menu.items.last)
        XCTAssertEqual(retract.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemRed)
        let bug = menu.items[2]
        _ = (bug.target as AnyObject?)?.perform(bug.action, with: bug)
        XCTAssertEqual(ran, ["bug"])
    }

    /// A picker's menu checks the current value; a disabled item stays visible but unusable; a submenu holds its items.
    func testCheckedDisabledAndSubmenuItems() {
        var ran: [String] = []
        let menu = AppNativeMenu.menu([
            AppNativeMenu.Item("English", checked: true) { ran.append("en") },
            AppNativeMenu.Item("Tiếng Việt") { ran.append("vi") },
            AppNativeMenu.Item("Off", enabled: false) { ran.append("off") },
            AppNativeMenu.Item("More", dividerBefore: true, children: [AppNativeMenu.Item("Inner") { ran.append("inner") }]),
        ])
        XCTAssertEqual(menu.items.map(\.title), ["English", "Tiếng Việt", "Off", "", "More"])
        XCTAssertEqual(menu.items[0].state, .on)
        XCTAssertEqual(menu.items[1].state, .off)
        XCTAssertFalse(menu.items[2].isEnabled)
        let more = menu.items[4]
        XCTAssertNil(more.action, "a submenu has no action of its own")
        XCTAssertEqual(more.submenu?.items.map(\.title), ["Inner"])
        let inner = more.submenu!.items[0]
        _ = (inner.target as AnyObject?)?.perform(inner.action, with: inner)
        XCTAssertEqual(ran, ["inner"])
    }

    /// A row's right-click menu is a native one: its entries keep their order, lines and checks, and a pick reports its
    /// index (the menu itself closes on any click, Esc or pick: macOS draws it).
    func testRightClickEntriesBecomeANativeMenuReportingThePickedIndex() {
        var picked: [Int] = []
        let entries = [AppMenuEntry(icon: "doc.on.doc", label: "Copy title"), AppMenuEntry(icon: "link", label: "Copy link"),
                       AppMenuEntry(icon: "checkmark.circle", label: "Select", checked: true, dividerBefore: true)]
        let menu = AppNativeMenu.menu(AppContextMenuModifier.items(entries) { picked.append($0) })
        XCTAssertEqual(menu.items.map(\.title), ["Copy title", "Copy link", "", "Select"])
        XCTAssertEqual(menu.items[3].state, .on)
        let select = menu.items[3]
        _ = (select.target as AnyObject?)?.perform(select.action, with: select)
        XCTAssertEqual(picked, [2])
    }
}
