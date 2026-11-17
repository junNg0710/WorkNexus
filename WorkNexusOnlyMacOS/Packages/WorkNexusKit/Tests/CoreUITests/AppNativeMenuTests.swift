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
}
