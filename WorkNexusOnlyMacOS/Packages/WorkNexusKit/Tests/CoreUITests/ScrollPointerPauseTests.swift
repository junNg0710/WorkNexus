import AppKit
import XCTest
@testable import CoreUI

@MainActor
final class ScrollPointerPauseTests: XCTestCase {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
    }

    func testAScrollPausesThePointerUntilItSettles() async throws {
        let pause = ScrollPointerPause(settle: 0.05)
        let w = window()
        XCTAssertTrue(w.areCursorRectsEnabled)
        pause.scrolled(in: w)
        XCTAssertFalse(w.areCursorRectsEnabled)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(w.areCursorRectsEnabled)
    }

    func testItStaysPausedWhileTheScrollGoesOn() async throws {
        let pause = ScrollPointerPause(settle: 0.15)
        let w = window()
        for _ in 0..<6 {
            pause.scrolled(in: w)
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertFalse(w.areCursorRectsEnabled)
        }
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(w.areCursorRectsEnabled)
    }

    /// The real signal: a scroll view's clip view moving, as SwiftUI's scroll views do on macOS.
    func testAScrollViewMovingPausesItsWindow() async throws {
        let pause = ScrollPointerPause(settle: 0.05)
        pause.start()
        let w = window()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 2000))
        w.contentView = scroll
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        XCTAssertFalse(w.areCursorRectsEnabled)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(w.areCursorRectsEnabled)
    }

    /// AppKit works out where a press would drag a window on every frame that changes its content: not during a scroll.
    func testTheWindowCannotBeDraggedDuringAScrollAndCanAgainAfterIt() async throws {
        let pause = ScrollPointerPause(settle: 0.05)
        let w = window()
        XCTAssertTrue(w.isMovable)
        pause.scrolled(in: w)
        XCTAssertFalse(w.isMovable)
        pause.scrolled(in: w)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(w.isMovable)
    }

    func testAWindowThatCouldNotBeMovedStaysSo() async throws {
        let pause = ScrollPointerPause(settle: 0.05)
        let w = window()
        w.isMovable = false
        pause.scrolled(in: w)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(w.isMovable)
        XCTAssertTrue(w.areCursorRectsEnabled)
    }
}
