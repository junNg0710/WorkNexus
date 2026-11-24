import XCTest
@testable import CoreUI

/// Where a wrap puts its children: the arithmetic behind `FlowLayout`, which keeps the answer for a width.
final class FlowLayoutRowsTests: XCTestCase {
    private let chip = CGSize(width: 40, height: 20)

    func testChildrenThatFitStayOnOneRow() {
        let r = FlowLayout.rows(200, [chip, chip, chip], spacing: 8, rowSpacing: 4)
        XCTAssertEqual(r.frames.map(\.minX), [0, 48, 96])
        XCTAssertEqual(r.frames.map(\.minY), [0, 0, 0])
        XCTAssertEqual(r.size, CGSize(width: 136, height: 20))
    }

    func testAChildThatDoesNotFitStartsANewRow() {
        let r = FlowLayout.rows(100, [chip, chip, chip], spacing: 8, rowSpacing: 4)
        XCTAssertEqual(r.frames.map(\.minX), [0, 48, 0])
        XCTAssertEqual(r.frames.map(\.minY), [0, 0, 24])
        XCTAssertEqual(r.size, CGSize(width: 88, height: 44))
    }

    func testARowIsAsTallAsItsTallestChild() {
        let r = FlowLayout.rows(100, [chip, CGSize(width: 40, height: 30), chip], spacing: 8, rowSpacing: 4)
        XCTAssertEqual(r.frames[2].minY, 34)
        XCTAssertEqual(r.size.height, 54)
    }

    func testNoChildrenTakeNoRoom() {
        XCTAssertEqual(FlowLayout.rows(100, [], spacing: 8, rowSpacing: 4).size, .zero)
    }
}
