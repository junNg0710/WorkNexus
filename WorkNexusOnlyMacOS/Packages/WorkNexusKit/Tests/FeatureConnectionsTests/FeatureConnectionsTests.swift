import XCTest
@testable import FeatureConnections

final class FeatureConnectionsTests: XCTestCase {
    func testModuleLoads() { XCTAssertEqual(FeatureConnectionsModule.name, "FeatureConnections") }
}
