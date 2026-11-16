import XCTest
@testable import CoreTools

final class CoreToolsTests: XCTestCase {
    func testModuleLoads() { XCTAssertEqual(CoreToolsModule.name, "CoreTools") }
}
