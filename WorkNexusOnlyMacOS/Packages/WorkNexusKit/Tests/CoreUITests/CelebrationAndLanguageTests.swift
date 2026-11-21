import SwiftUI
import XCTest
@testable import CoreUI

final class FireworksTests: XCTestCase {
    func testAShowIsRepeatableForASeed() {
        let size = CGSize(width: 800, height: 600)
        let a = Fireworks.sparks(in: size, seed: 7), b = Fireworks.sparks(in: size, seed: 7), c = Fireworks.sparks(in: size, seed: 8)
        XCTAssertEqual(a.count, 12 * 48)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertTrue(a.allSatisfy { $0.origin.x >= 0 && $0.origin.x <= size.width && $0.origin.y <= size.height * 0.56 && $0.colour < 5 })
    }

    func testASparkLivesOnlyWithinItsBurst() throws {
        let spark = try XCTUnwrap(Fireworks.sparks(in: CGSize(width: 800, height: 600), seed: 1).first)
        XCTAssertNil(Fireworks.frame(of: spark, at: max(spark.start - 0.01, -1)))
        let start = try XCTUnwrap(Fireworks.frame(of: spark, at: spark.start))
        XCTAssertEqual(start.at.x, spark.origin.x, accuracy: 0.001)
        XCTAssertEqual(start.opacity, 1, accuracy: 0.001)
        XCTAssertNil(Fireworks.frame(of: spark, at: spark.start + 0.41))
        let late = try XCTUnwrap(Fireworks.frame(of: spark, at: spark.start + 0.3))
        XCTAssertLessThan(late.opacity, 1)
    }

    @MainActor func testControllerTicks() {
        let c = CelebrationController(); c.celebrate(); c.celebrate()
        XCTAssertEqual(c.tick, 2)
    }
}

final class CustomColorTests: XCTestCase {
    func testArgbOfAnHsvColour() {
        XCTAssertEqual(CustomColorDialog.argb(HsvColor(hex: "#3B82F6")!), 0xFF3B82F6)
        XCTAssertEqual(CustomColorDialog.argb(HsvColor(h: 0, s: 0, v: 1)), 0xFFFFFFFF)
    }
}

final class AppLanguageTests: XCTestCase {
    func testUnknownLanguageFallsBackToEnglishAndStringsStillResolve() {
        AppLanguage.apply("vi"); XCTAssertEqual(AppLanguage.current, "vi")
        AppLanguage.apply("zh-Hans"); XCTAssertEqual(AppLanguage.current, "zh-Hans")
        XCTAssertEqual(AppLanguage.nativeName("zh-Hans"), "简体中文")
        AppLanguage.apply("xx"); XCTAssertEqual(AppLanguage.current, "en")
        XCTAssertEqual(AppLanguage.locale.identifier, "en")
        XCTAssertEqual(appString("someUnknownKey", "Fallback"), "Fallback")
    }
}
