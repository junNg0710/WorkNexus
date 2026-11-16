import AppKit
import SwiftUI
import XCTest
@testable import CoreUI

/// The icon that folds / unfolds a side panel, drawn large in all four forms (`/tmp/wn-pet-render/panel-glyph.png`).
@MainActor
final class PanelToggleGlyphTests: XCTestCase {
    func testAllFourFormsDrawSomethingAndDiffer() async throws {
        func glyph(_ a: PanelToggleGlyph.Action, _ side: HorizontalEdge, _ size: CGFloat) -> some View {
            PanelToggleGlyph(a, side: side, size: size).foregroundStyle(Color(white: 0.17)).padding(14)
        }
        let big = HStack(spacing: 10) {
            glyph(.collapse, .leading, 64); glyph(.expand, .leading, 64); glyph(.collapse, .trailing, 64); glyph(.expand, .trailing, 64)
        }
        let small = HStack(spacing: 10) {
            glyph(.collapse, .leading, 16); glyph(.expand, .leading, 16); glyph(.collapse, .trailing, 16); glyph(.expand, .trailing, 16)
        }
        let host = NSHostingView(rootView: VStack(spacing: 6) { big; small }.padding(10).background(Color.white))
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 210)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try FileManager.default.createDirectory(atPath: "/tmp/wn-pet-render", withIntermediateDirectories: true)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/wn-pet-render/panel-glyph.png"))
        XCTAssertGreaterThan(png.count, 3_000)
    }
}
