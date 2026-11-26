import AppKit
import XCTest
@testable import CoreUI

@MainActor
final class PointerMovePaceTests: XCTestCase {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
    }

    func testAMoveIsHandledOnceTheIntervalHasPassed() {
        var gate = PointerMoveGate(interval: 0.1)
        XCTAssertNil(gate.wait(at: 5))
        XCTAssertEqual(gate.wait(at: 5.04) ?? 0, 0.06, accuracy: 0.0001)
        XCTAssertEqual(gate.wait(at: 5.09) ?? 0, 0.01, accuracy: 0.0001)
        XCTAssertNil(gate.wait(at: 5.1))
        XCTAssertNotNil(gate.wait(at: 5.15))
    }

    func testTheWaitingMoveBeingHandledStartsTheIntervalAgain() {
        var gate = PointerMoveGate(interval: 0.1)
        XCTAssertNil(gate.wait(at: 5))
        gate.handled(at: 5.1)
        XCTAssertEqual(gate.wait(at: 5.12) ?? 0, 0.08, accuracy: 0.0001)
        XCTAssertNil(gate.wait(at: 5.2))
    }

    func testMovesThatComeTooSoonAreHandledOnceAtTheirTurn() async throws {
        var sent: [NSEvent] = []
        let pace = PointerMovePace(rate: 10) { sent.append($0) }
        let w = window()
        let t = ProcessInfo.processInfo.systemUptime
        XCTAssertTrue(pace.admits(moveAt: t, in: w))
        XCTAssertFalse(pace.admits(moveAt: t + 0.01, in: w))
        XCTAssertFalse(pace.admits(moveAt: t + 0.02, in: w))
        XCTAssertFalse(pace.admits(moveAt: t + 0.03, in: w))
        XCTAssertTrue(sent.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.type, .mouseMoved)
        // The turn taken starts the interval again: a move right after it waits.
        let turn = try XCTUnwrap(sent.first).timestamp
        XCTAssertFalse(pace.admits(moveAt: turn + 0.02, in: w))
    }

    func testAMoveHandledMeanwhileTakesTheTurn() async throws {
        var sent: [NSEvent] = []
        let pace = PointerMovePace(rate: 10) { sent.append($0) }
        let w = window()
        let t = ProcessInfo.processInfo.systemUptime
        XCTAssertTrue(pace.admits(moveAt: t, in: w))
        XCTAssertFalse(pace.admits(moveAt: t + 0.05, in: w))
        // The main thread was busy past the turn, and a real move arrived first.
        XCTAssertTrue(pace.admits(moveAt: t + 0.12, in: w))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(sent.isEmpty)
    }

    func testNothingIsSentWhenNoMoveWaits() async throws {
        var sent: [NSEvent] = []
        let pace = PointerMovePace(rate: 10) { sent.append($0) }
        let w = window()
        XCTAssertTrue(pace.admits(moveAt: ProcessInfo.processInfo.systemUptime, in: w))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(sent.isEmpty)
    }
}
