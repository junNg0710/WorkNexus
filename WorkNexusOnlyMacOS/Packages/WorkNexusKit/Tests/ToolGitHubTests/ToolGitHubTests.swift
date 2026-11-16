import XCTest
@testable import ToolGitHub

final class ToolGitHubTests: XCTestCase {
    func testModuleLoads() { XCTAssertEqual(ToolGitHubModule.name, "ToolGitHub") }
}
