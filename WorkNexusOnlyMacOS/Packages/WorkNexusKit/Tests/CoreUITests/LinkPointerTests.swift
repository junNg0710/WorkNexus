import AppKit
import SwiftUI
import XCTest
@testable import CoreUI

@MainActor
final class LinkPointerTests: XCTestCase {
    /// The hand shows over a link and not over the words around it, also once the text wraps.
    func testAPointIsOnALinkOnlyWithinTheLinksGlyphs() {
        var text = AttributedString("see ")
        var link = AttributedString("https://example.com/a"); link.link = URL(string: "https://example.com/a")
        text += link; text += AttributedString(" and some plain words after it")
        let font = NSFont.systemFont(ofSize: 14), hit = TextLinkHitTest()
        let laid = TextLinkHitTest.attributed(text, font: font, lineSpacing: 0)
        let seeWidth = NSAttributedString(string: "see ", attributes: [.font: font]).size().width
        let linkWidth = NSAttributedString(string: "https://example.com/a", attributes: [.font: font]).size().width
        XCTAssertNotNil(laid.attribute(.link, at: 5, effectiveRange: nil))
        let y: CGFloat = 8
        XCTAssertFalse(hit.isOnLink(CGPoint(x: seeWidth / 2, y: y), text: text, font: font, lineSpacing: 0, width: 600))
        XCTAssertTrue(hit.isOnLink(CGPoint(x: seeWidth + linkWidth / 2, y: y), text: text, font: font, lineSpacing: 0, width: 600))
        XCTAssertFalse(hit.isOnLink(CGPoint(x: seeWidth + linkWidth + 40, y: y), text: text, font: font, lineSpacing: 0, width: 600))
        XCTAssertFalse(hit.isOnLink(CGPoint(x: 590, y: y), text: text, font: font, lineSpacing: 0, width: 600), "past the line's end")
        XCTAssertFalse(hit.isOnLink(CGPoint(x: 10, y: y), text: AttributedString("no links here"), font: font, lineSpacing: 0, width: 600))
    }
}
