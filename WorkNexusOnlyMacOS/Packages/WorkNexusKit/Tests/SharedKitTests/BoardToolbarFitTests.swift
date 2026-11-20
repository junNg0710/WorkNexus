import CoreGraphics
import XCTest
@testable import SharedKit

/// The toolbar's arrangement for its width: labels on the view modes while there is room, then icons only, then the
/// scopes folded into a menu, then no search field — the order `ViewThatFits` used to find by laying out all four.
final class BoardToolbarFitTests: XCTestCase {
    private let fit = BoardToolbarFit(scopesTabs: 220, scopesMenu: 110, modesWithLabels: 150, modesIconOnly: 70, others: 120)
    private func layout(_ width: CGFloat) -> BoardToolbarFit.Layout { fit.layout(available: width, searchMin: 160, spacing: 6, pieces: 6) }

    func testItKeepsTheWidestArrangementThatFits() {
        // 220 + 120 + 150 + 160 + 5 × 6 = 680
        XCTAssertEqual(layout(680), BoardToolbarFit.layouts[0])
        XCTAssertEqual(layout(679), BoardToolbarFit.layouts[1], "the view modes lose their labels first")
        XCTAssertEqual(layout(600), BoardToolbarFit.layouts[1])
        XCTAssertEqual(layout(599), BoardToolbarFit.layouts[2], "then the scopes fold into a menu")
        XCTAssertEqual(layout(489), BoardToolbarFit.layouts[3], "then the search field goes")
        XCTAssertEqual(layout(10), BoardToolbarFit.layouts[3], "the narrowest when nothing fits")
    }

    func testUnmeasuredPiecesShowEverythingUntilTheirWidthsArrive() {
        XCTAssertEqual(BoardToolbarFit().layout(available: 400, searchMin: 160, spacing: 6, pieces: 6), BoardToolbarFit.layouts[0])
    }
}
