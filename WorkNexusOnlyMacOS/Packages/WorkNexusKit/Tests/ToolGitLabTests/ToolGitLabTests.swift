import XCTest
@testable import ToolGitLab

final class ToolGitLabTests: XCTestCase {
    func testModuleLoads() { XCTAssertEqual(ToolGitLabModule.name, "ToolGitLab") }
}
