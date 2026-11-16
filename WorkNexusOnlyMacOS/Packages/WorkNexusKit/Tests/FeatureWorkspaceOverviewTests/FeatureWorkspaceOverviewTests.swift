import XCTest
@testable import FeatureWorkspaceOverview

final class FeatureWorkspaceOverviewTests: XCTestCase {
    func testModuleLoads() { XCTAssertEqual(FeatureWorkspaceOverviewModule.name, "FeatureWorkspaceOverview") }
}
