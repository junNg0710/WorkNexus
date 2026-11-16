import XCTest
@testable import FeatureNotifications

final class FeatureNotificationsTests: XCTestCase {
    func testFeatureNameIsStable() { XCTAssertEqual(NotificationsFeature.name, "FeatureNotifications") }
}
