import AppKit
import Observation
import SwiftUI
import XCTest
@testable import FeatureChat

/// `ChatColumn` places its children with the sizes it measured them at. Sizes kept from one pass must not outlive a
/// child that changed.
@MainActor
final class ChatColumnCacheTests: XCTestCase {
    @Observable final class Box { var height: CGFloat = 40 }
    final class Probe { var y: CGFloat = -1 }

    private struct Column: View {
        let box: Box
        let probe: Probe
        var body: some View {
            ChatColumn {
                Color.red.frame(width: 100, height: box.height)
                Color.blue.frame(width: 100, height: 10)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("column")).minY } action: { probe.y = $0 }
            }
            .coordinateSpace(name: "column")
            .frame(width: 300, height: 400, alignment: .topLeading)
        }
    }

    func testAChildThatGrowsMovesTheOneBelowIt() async throws {
        let box = Box(), probe = Probe()
        let host = NSHostingView(rootView: Column(box: box, probe: probe))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        func settle() async throws { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(30)) } }
        try await settle()
        XCTAssertEqual(probe.y, 40, accuracy: 0.5)
        box.height = 90
        try await settle()
        XCTAssertEqual(probe.y, 90, accuracy: 0.5, "placed with the size of this pass, not the one before")
        box.height = 20
        try await settle()
        XCTAssertEqual(probe.y, 20, accuracy: 0.5)
    }
}
