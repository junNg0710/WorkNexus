/// Ported from: test/features/chat (bubble_tail geometry; checks the path of the tailed bubble shape)
import SwiftUI
import XCTest
@testable import FeatureChat

final class BubbleShapeTests: XCTestCase {
    private let rect = CGRect(x: 100, y: 50, width: 200, height: 60)
    private let w = BubbleTail.width, h = BubbleTail.height

    private func outline(_ kind: BubbleTailKind, _ c: BubbleCorners, left: Bool, tip: CGFloat? = nil) -> Path {
        BubbleShape.outline(in: rect, kind: kind, corners: c, tailOnLeft: left, tipOffset: tip)
    }

    func testTriangleTailSticksOutOnTheAvatarSide() {
        let c = BubbleCorners(all: 12)
        let left = outline(.triangleTop, c, left: true).boundingRect
        XCTAssertEqual(left.minX, rect.minX - w, accuracy: 0.01)
        XCTAssertEqual(left.maxX, rect.maxX, accuracy: 0.01)
        XCTAssertEqual(left.minY, rect.minY, accuracy: 0.01)
        XCTAssertEqual(left.maxY, rect.maxY, accuracy: 0.01)
        let right = outline(.triangleTop, c, left: false).boundingRect
        XCTAssertEqual(right.maxX, rect.maxX + w, accuracy: 0.01)
        XCTAssertEqual(right.minX, rect.minX, accuracy: 0.01)
    }

    func testCurlTailLeavesTheBottomCorner() {
        // The tail-side bottom corner is square: the curl takes it.
        let c = BubbleCorners(topLeft: 16, topRight: 16, bottomLeft: 0, bottomRight: 16)
        let box = outline(.curlBottom, c, left: true).boundingRect
        XCTAssertEqual(box.minX, rect.minX - w, accuracy: 0.01)
        XCTAssertEqual(box.maxY, rect.maxY, accuracy: 0.01)
        let p = outline(.curlBottom, c, left: true)
        XCTAssertTrue(p.contains(CGPoint(x: rect.minX - 1, y: rect.maxY - 0.5)), "the curl's root is part of the shape")
        XCTAssertFalse(p.contains(CGPoint(x: rect.minX - w + 0.5, y: rect.maxY - h)), "above the curl nothing sticks out")
        let own = outline(.curlBottom, BubbleCorners(topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 0), left: false)
        XCTAssertEqual(own.boundingRect.maxX, rect.maxX + w, accuracy: 0.01)
        XCTAssertTrue(own.contains(CGPoint(x: rect.maxX + 1, y: rect.maxY - 0.5)))
    }

    func testTrianglePointsAtTheAvatarCentre() {
        // The tip is the avatar's centre: 20 below the top for a 40pt avatar.
        let c = BubbleCorners(all: 12)
        let apex = BubbleShape.triangleApexY(rect: rect, corners: c, tailOnLeft: true, tipOffset: 20)
        XCTAssertEqual(apex, rect.minY + 20, accuracy: 0.001)
        let p = outline(.triangleTop, c, left: true, tip: 20)
        XCTAssertTrue(p.contains(CGPoint(x: rect.minX - 2, y: apex)))
        XCTAssertFalse(p.contains(CGPoint(x: rect.minX - 2, y: apex + h * 0.6)), "below the triangle is empty")
        XCTAssertFalse(p.contains(CGPoint(x: rect.minX - 2, y: apex - h * 0.6)), "above the triangle is empty")
        // Mirrored for an own message: same height, other side.
        let mirrored = outline(.triangleTop, c, left: false, tip: 20)
        XCTAssertTrue(mirrored.contains(CGPoint(x: rect.maxX + 2, y: apex)))
        XCTAssertFalse(mirrored.contains(CGPoint(x: rect.minX - 2, y: apex)))
    }

    func testTriangleDefaultsToJustUnderTheCorner() {
        let c = BubbleCorners(all: 4)
        let apex = BubbleShape.triangleApexY(rect: rect, corners: c, tailOnLeft: true, tipOffset: nil)
        XCTAssertEqual(apex, rect.minY + BubbleTail.topInset + h * 0.5, accuracy: 0.001)
    }

    func testTriangleStaysClearOfTheCornerArcsSoItNeverKinks() {
        let c = BubbleCorners(all: 12)
        // A tip near the top would start inside the top-left arc.
        let high = BubbleShape.triangleTop(rect: rect, corners: c, tailOnLeft: true, tipOffset: 2)
        XCTAssertEqual(high, 12, accuracy: 0.001)
        // A tip near the bottom would run into the bottom-left arc.
        let low = BubbleShape.triangleTop(rect: rect, corners: c, tailOnLeft: true, tipOffset: 500)
        XCTAssertEqual(low, rect.height - 12 - h * 0.7, accuracy: 0.001)
        XCTAssertLessThanOrEqual(low + h * 0.7, rect.height - 12 + 0.001)
        // The rounded corner is still rounded next to the triangle.
        let p = outline(.triangleTop, c, left: true, tip: 2)
        XCTAssertFalse(p.contains(CGPoint(x: rect.minX + 0.5, y: rect.minY + 0.5)))
        XCTAssertTrue(p.contains(CGPoint(x: rect.minX + 12, y: rect.minY + 12)))
    }

    func testTinyBubbleKeepsTheTriangleInsideTheBox() {
        let tiny = CGRect(x: 0, y: 0, width: 80, height: 20)
        let c = BubbleCorners(all: 12)
        let top = BubbleShape.triangleTop(rect: tiny, corners: c, tailOnLeft: true, tipOffset: 500)
        // Upper bound never drops below the lower one (no inverted clamp range).
        XCTAssertGreaterThanOrEqual(top, 12)
    }

    func testMirroredCornersSwapSides() {
        let c = BubbleCorners(topLeft: 1, topRight: 2, bottomLeft: 3, bottomRight: 4)
        XCTAssertEqual(c.mirrored, BubbleCorners(topLeft: 2, topRight: 1, bottomLeft: 4, bottomRight: 3))
    }

    func testBodyIsInsideTheBoxAndRoundedCornersCutIt() {
        let p = outline(.triangleTop, BubbleCorners(all: 12), left: true)
        XCTAssertTrue(p.contains(CGPoint(x: rect.midX, y: rect.midY)))
        XCTAssertFalse(p.contains(CGPoint(x: rect.maxX - 0.5, y: rect.minY + 0.5)))
        XCTAssertFalse(p.contains(CGPoint(x: rect.maxX + 0.5, y: rect.midY)))
    }

    func testShapeIsASwiftUIShapeWithTheSameOutline() {
        let c = BubbleCorners(all: 12)
        let shape = BubbleShape(kind: .triangleTop, corners: c, tailOnLeft: false, tipOffset: 20)
        XCTAssertEqual(shape.path(in: rect).boundingRect, outline(.triangleTop, c, left: false, tip: 20).boundingRect)
    }
}
