import XCTest
@testable import CoreUI

final class CoreUITests: XCTestCase {
    func testModuleLoads() { XCTAssertEqual(CoreUIModule.name, "CoreUI") }
}

/// The catalog turns `{count}` into `%1$@`: callers that fill names still fill them, and a number never crashes a format.
final class PlaceholderNamingTests: XCTestCase {
    func testPositionalPlaceholdersAreNamedAfterTheFallback() {
        XCTAssertEqual(namingPlaceholders("Show all %1$@ lines", like: "Show all {count} lines"), "Show all {count} lines")
        XCTAssertEqual(namingPlaceholders("%2$@ đã thêm %1$@", like: "{who} added {what}"), "{what} đã thêm {who}")
        XCTAssertEqual(namingPlaceholders("Translate with %1$@", like: "Translate with %1$@"), "Translate with %1$@")
        XCTAssertEqual(namingPlaceholders("No placeholders", like: "Show {count}"), "No placeholders")
    }

    func testANumberForAnObjectPlaceholderGoesInAsText() {
        XCTAssertEqual(appFormat("noSuchKeyForTests", "Use at most %1$@ characters", 30), "Use at most 30 characters")
        XCTAssertEqual(appFormat("noSuchKeyForTests2", "%d left", 3), "3 left")
    }
}
