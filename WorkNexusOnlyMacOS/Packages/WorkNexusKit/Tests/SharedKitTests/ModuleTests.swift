import XCTest
@testable import SharedKit

final class ModuleTests: XCTestCase {
    func testModuleLoads() { XCTAssertEqual(SharedKitModule.name, "SharedKit") }
}
