import AppKit
import SwiftUI
import XCTest
@testable import CoreUI

/// Ported from: test/core/dropped_files_test.dart, test/core/custom_color_dialog_test.dart (+ the editor's colour grid
/// and the image zoom maths).
@MainActor
final class DropColorTests: XCTestCase {
    // MARK: dropped files

    func testKnowsTheImagesTheEditorShowsInline() {
        XCTAssertTrue(DroppedFiles.isInlineImageName("shot.PNG"))
        XCTAssertTrue(DroppedFiles.isInlineImageName("photo.jpeg"))
        XCTAssertFalse(DroppedFiles.isInlineImageName("report.pdf"))
        XCTAssertFalse(DroppedFiles.isInlineImageName("no-extension"))
    }

    func testSplitsDroppedFilesIntoImagesAndTheRestInOrder() {
        let bytes = Data()
        let split = DroppedFiles.split([DroppedFile(name: "a.png", bytes: bytes), DroppedFile(name: "log.txt", bytes: bytes),
                                        DroppedFile(name: "b.gif", bytes: bytes)])
        XCTAssertEqual(split.images.map(\.name), ["a.png", "b.gif"])
        XCTAssertEqual(split.others.map(\.name), ["log.txt"])
    }

    func testReadingDroppedURLsSkipsFoldersAndFailsOnAnUnreadableFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wn-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("folder"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try Data("hi".utf8).write(to: file)
        let read = await DroppedFiles.read([file, dir.appendingPathComponent("folder")])
        XCTAssertEqual(read, [DroppedFile(name: "a.txt", bytes: Data("hi".utf8))])
        let missing = await DroppedFiles.read([dir.appendingPathComponent("nope.txt")])
        XCTAssertNil(missing)
    }

    func testDropZonesCountTheTargetsFilesHoverOver() {
        let zones = FileDropZonesModel()
        zones.enter(); XCTAssertEqual(zones.hovering, 1)
        zones.enter(); zones.leave(); zones.leave(); zones.leave()
        XCTAssertEqual(zones.hovering, 0, "never below zero")
    }

    // MARK: editor colours

    func testTheEditorOffersA24SwatchGridInSixColumns() {
        XCTAssertEqual(EditorTextColors.swatches.count, 24)
        XCTAssertEqual(EditorTextColors.columns, 6)
        XCTAssertEqual(Set(EditorTextColors.swatches).count, 24, "no duplicates")
        XCTAssertTrue(EditorTextColors.swatches.allSatisfy { EditorTextColors.normalized($0) == $0 })
        XCTAssertEqual(EditorTextColors.swatches.last, "#000000")
    }

    func testColoursNormaliseToLowerCaseSixDigitHex() {
        XCTAssertEqual(EditorTextColors.normalized("#E03E2D"), "#e03e2d")
        XCTAssertEqual(EditorTextColors.normalized("#f00"), "#ff0000")
        XCTAssertNil(EditorTextColors.normalized("red"))
        XCTAssertNil(EditorTextColors.normalized("#12345"))
        XCTAssertNil(EditorTextColors.normalized(nil))
    }

    func testACheckReadsOnItsSwatch() {
        XCTAssertTrue(EditorTextColors.prefersDarkInk(on: "#ffffff"))
        XCTAssertTrue(EditorTextColors.prefersDarkInk(on: "#fbeeb8"))
        XCTAssertFalse(EditorTextColors.prefersDarkInk(on: "#000000"))
        XCTAssertFalse(EditorTextColors.prefersDarkInk(on: "#163e5e"))
    }

    // MARK: custom colour (custom_color_dialog_test)

    func testParseHexReadsRrggbbInAnyCaseWithOrWithoutHash() {
        XCTAssertEqual(HsvColor(hex: "#3b82f6")?.hex, "#3B82F6")
        XCTAssertEqual(HsvColor(hex: "3B82F6")?.hex, "#3B82F6")
        XCTAssertEqual(HsvColor(hex: " #3B82F6 ")?.hex, "#3B82F6")
        XCTAssertEqual(HsvColor(hex: "#00000A")?.hex, "#00000A")
    }

    func testParseHexRejectsMalformedInput() {
        for bad in ["", "#3B82F", "#3B82F6FF", "#GGGGGG"] { XCTAssertNil(HsvColor(hex: bad), bad) }
    }

    func testAGreyKeepsNoHueOfItsOwn() {
        let grey = HsvColor(hex: "#808080")!
        XCTAssertEqual(grey.s, 0, accuracy: 1e-9)
        XCTAssertEqual(grey.hex, "#808080")
    }

    // MARK: image zoom

    func testZoomingAboutAPointKeepsThePointUnderThePointer() {
        let q = CGPoint(x: 40, y: -20)
        let z = ImageZoom().zoomed(to: 2.5, about: q)
        // The content point under q before: u = q (scale 1, no offset); after: q = offset + scale * u.
        XCTAssertEqual(z.offset.width + z.scale * q.x, q.x, accuracy: 1e-9)
        XCTAssertEqual(z.offset.height + z.scale * q.y, q.y, accuracy: 1e-9)
        // Zooming further about the same point keeps it there.
        let z2 = z.zoomed(to: 4, about: q)
        XCTAssertEqual(z2.offset.width + z2.scale * q.x, q.x, accuracy: 1e-9)
    }

    func testDoubleClickZoomsInThenBackToFit() {
        let q = CGPoint(x: 10, y: 10)
        let zoomed = ImageZoom().toggled(about: q, zoomedScale: 2.5)
        XCTAssertEqual(zoomed.scale, 2.5)
        XCTAssertEqual(zoomed.toggled(about: q, zoomedScale: 2.5), ImageZoom())
    }

    func testZoomIsClampedToTheLimits() {
        XCTAssertEqual(ImageZoom().zoomed(to: 99, about: .zero, minScale: 0.5, maxScale: 5).scale, 5)
        XCTAssertEqual(ImageZoom().zoomed(to: 0.01, about: .zero, minScale: 0.5, maxScale: 5).scale, 0.5)
    }

    func testTheViewerFollowsItsWindowWithinLimits() {
        // The share of the space picked with the viewer's bigger / smaller buttons (large by default), no fixed cap.
        XCTAssertEqual(AdaptiveViewerFrame<EmptyView>.size(in: CGSize(width: 1000, height: 800), expanded: false), CGSize(width: 920, height: 736))
        XCTAssertEqual(AdaptiveViewerFrame<EmptyView>.size(in: CGSize(width: 2000, height: 1400), expanded: false, level: .medium),
                       CGSize(width: 2000 * 0.76, height: 1400 * 0.76))
        XCTAssertEqual(AdaptiveViewerFrame<EmptyView>.size(in: CGSize(width: 300, height: 200), expanded: false), CGSize(width: 300, height: 200))
        XCTAssertEqual(AdaptiveViewerFrame<EmptyView>.size(in: CGSize(width: 1000, height: 800), expanded: true), CGSize(width: 1000, height: 800))
    }
}
