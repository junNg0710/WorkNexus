import XCTest
@testable import CoreDomain

final class CoreDomainTests: XCTestCase {
    func testModuleLoads() { XCTAssertEqual(CoreDomainModule.name, "CoreDomain") }
}
