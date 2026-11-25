import AppKit
@testable import CoreUI
import XCTest

/// A click on a menu button is told from a held press before the menu opens.
@MainActor
final class MenuPressTests: XCTestCase {
    private func window() -> NSWindow {
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        w.orderBack(nil)
        return w
    }

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    func testAReleaseRightAfterThePressIsAClickAndIsTakenOffTheQueue() {
        let w = window()
        defer { w.orderOut(nil) }
        let press = mouse(.leftMouseDown, at: NSPoint(x: 50, y: 50), in: w)
        NSApp.postEvent(mouse(.leftMouseUp, at: NSPoint(x: 51, y: 50), in: w), atStart: false)
        XCTAssertTrue(MenuPress.isClick(press, in: w, within: 0.5))
        XCTAssertNil(w.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .eventTracking, dequeue: true),
                     "the release is gone: nothing is left to close the menu that opens next")
    }

    func testAPressStillHeldIsNotAClick() {
        let w = window()
        defer { w.orderOut(nil) }
        let press = mouse(.leftMouseDown, at: NSPoint(x: 50, y: 50), in: w)
        let began = Date()
        XCTAssertFalse(MenuPress.isClick(press, in: w, within: 0.08))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(began), 0.07, "it waits the click time out")
    }

    func testAPressDraggedAwayOpensTheMenuAtOnce() {
        let w = window()
        defer { w.orderOut(nil) }
        let press = mouse(.leftMouseDown, at: NSPoint(x: 50, y: 50), in: w)
        NSApp.postEvent(mouse(.leftMouseDragged, at: NSPoint(x: 50, y: 30), in: w), atStart: false)
        let began = Date()
        XCTAssertFalse(MenuPress.isClick(press, in: w, within: 2))
        XCTAssertLessThan(Date().timeIntervalSince(began), 1, "it does not wait once the pointer is on its way")
    }

    func testWithoutAWindowThereIsNothingToWaitFor() {
        let w = window()
        let press = mouse(.leftMouseDown, at: NSPoint(x: 50, y: 50), in: w)
        w.orderOut(nil)
        XCTAssertFalse(MenuPress.isClick(press, in: nil))
    }
}
