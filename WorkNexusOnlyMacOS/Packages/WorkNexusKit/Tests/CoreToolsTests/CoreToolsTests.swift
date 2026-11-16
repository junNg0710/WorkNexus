import XCTest
@testable import CoreTools

final class CoreToolsTests: XCTestCase {
    func testModuleLoads() { XCTAssertEqual(CoreToolsModule.name, "CoreTools") }
}


final class ToolSectionUnreadTests: XCTestCase {
    @MainActor func testUnreadCountIsOptionalAndReadOnDemand() {
        let plain = ToolSection(id: "a", label: "A", systemImage: "circle", scopeKind: .none)
        XCTAssertNil(plain.unreadCount)
        nonisolated(unsafe) var unread = 2
        let badged = ToolSection(id: "b", label: "B", systemImage: "circle", scopeKind: .none, unreadCount: { unread })
        XCTAssertEqual(badged.unreadCount?(), 2)
        unread = 7
        XCTAssertEqual(badged.unreadCount?(), 7)
    }
}
