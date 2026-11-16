import AppKit
import SwiftUI
import XCTest
@testable import FeatureChat

/// A bubble is as wide as its content needs, up to its cap - so what sits beside it sits beside the bubble.
@MainActor
final class HuggingMaxWidthTests: XCTestCase {
    private final class Box { var size = CGSize.zero }

    private func measure<V: View>(_ view: V, offered: CGFloat = 1000) async throws -> CGSize {
        let box = Box()
        let probe = view.background(GeometryReader { g in Color.clear.onAppear { box.size = g.size } })
        let host = NSHostingView(rootView: HStack(spacing: 0) { probe; Spacer(minLength: 0) }.frame(width: offered, height: 200, alignment: .topLeading))
        host.frame = NSRect(x: 0, y: 0, width: offered, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        return box.size
    }

    func testAShortChildKeepsItsOwnWidthEvenWhenMuchMoreRoomIsOffered() async throws {
        let short = try await measure(Text("Ok anh").padding(8).hugging(maxWidth: 400))
        XCTAssertLessThan(short.width, 120)
        // With the old frame the same child took the whole cap.
        let framed = try await measure(Text("Ok anh").padding(8).frame(maxWidth: 400, alignment: .leading))
        XCTAssertEqual(framed.width, 400, accuracy: 1)
    }

    func testAChildThatFillsGetsTheCapAndALongTextWrapsAtIt() async throws {
        let fills = try await measure(Color.gray.frame(maxWidth: .infinity, minHeight: 20).hugging(maxWidth: 400))
        XCTAssertEqual(fills.width, 400, accuracy: 1)
        let long = try await measure(Text(String(repeating: "word ", count: 80)).hugging(maxWidth: 400))
        XCTAssertEqual(long.width, 400, accuracy: 2)
        XCTAssertGreaterThan(long.height, 40)
        // And never wider than what is offered.
        let narrow = try await measure(Color.gray.frame(maxWidth: .infinity, minHeight: 20).hugging(maxWidth: 400), offered: 300)
        XCTAssertEqual(narrow.width, 300, accuracy: 1)
    }
}
