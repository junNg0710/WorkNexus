/// Ported from: lib/features/chat/presentation/widgets/chat_avatar_crop_view.dart (frame maths)
import CoreGraphics
import XCTest
@testable import FeatureChat

final class AvatarCropGeometryTests: XCTestCase {
    private func geometry() -> AvatarCropGeometry {
        // A 2000x1000 picture in a 532x332 area with 32 px grips: scale = min(500/2000, 300/1000) = 0.25.
        AvatarCropGeometry(imageSize: CGSize(width: 2000, height: 1000), maxSize: CGSize(width: 532, height: 332), grip: 32)
    }

    func testStartsOnTheBiggestCentredSquare() {
        let g = geometry()
        XCTAssertEqual(g.scale, 0.25, accuracy: 1e-9)
        XCTAssertEqual(g.shown, CGSize(width: 500, height: 250))
        XCTAssertEqual(g.frame, CGRect(x: 125, y: 0, width: 250, height: 250))
        let crop = g.crop
        XCTAssertEqual(crop.left, 500, accuracy: 1e-9); XCTAssertEqual(crop.top, 0, accuracy: 1e-9); XCTAssertEqual(crop.side, 1000, accuracy: 1e-9)
    }

    func testMovingStopsAtThePicturesEdges() {
        var g = geometry()
        g.move(by: CGSize(width: -1000, height: 40))
        XCTAssertEqual(g.frame.origin, CGPoint(x: 0, y: 0))
        g.move(by: CGSize(width: 9999, height: 0))
        XCTAssertEqual(g.frame.maxX, 500)
    }

    func testResizingFromACornerKeepsTheOppositeCornerAndStaysInside() {
        var g = geometry()
        g.move(by: CGSize(width: -125, height: 0))               // frame at 0,0, side 250
        let corner = AvatarCropGeometry.Corner(x: 1, y: 1)
        var r = g.beginResize(corner)
        g.resize(corner, by: CGSize(width: -100, height: -100), &r)
        XCTAssertEqual(g.frame, CGRect(x: 0, y: 0, width: 150, height: 150))
        g.resize(corner, by: CGSize(width: 1000, height: 1000), &r)   // as far as the picture allows (250 high)
        XCTAssertEqual(g.frame, CGRect(x: 0, y: 0, width: 250, height: 250))
        // Never smaller than two grips.
        g.resize(corner, by: CGSize(width: -5000, height: -5000), &r)
        XCTAssertEqual(g.frame.width, 64)
    }

    func testResizingFromTheTopLeftAnchorsTheBottomRight() {
        var g = geometry()
        let corner = AvatarCropGeometry.Corner(x: -1, y: -1)
        var r = g.beginResize(corner)
        g.resize(corner, by: CGSize(width: 50, height: 50), &r)
        XCTAssertEqual(g.frame.maxX, 375, accuracy: 1e-9)
        XCTAssertEqual(g.frame.maxY, 250, accuracy: 1e-9)
        XCTAssertEqual(g.frame.width, 200, accuracy: 1e-9)
    }
}
