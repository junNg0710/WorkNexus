import AppKit
import SwiftUI
import XCTest
@testable import CoreUI

/// A kept place that is not on screen keeps the size it last had there, and stays awake for one frame after it leaves.
@MainActor
final class KeepAliveLayoutTests: XCTestCase {
    private final class Sizes { var byKey: [String: CGSize] = [:] }

    private func stack(active: String, _ sizes: Sizes) -> some View {
        KeepAliveLayout {
            ForEach(["a", "b"], id: \.self) { key in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(GeometryReader { g in
                        Color.clear.onChange(of: g.size, initial: true) { _, size in sizes.byKey[key] = size }
                    })
                    .keepAlivePlace(key, active: key == active)
            }
        }
    }

    func testAHiddenPlaceKeepsTheSizeItLastHadOnScreen() async throws {
        let sizes = Sizes()
        let host = NSHostingView(rootView: stack(active: "b", sizes))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(sizes.byKey["b"], CGSize(width: 400, height: 300))
        // Never on screen yet: as large as the stack.
        XCTAssertEqual(sizes.byKey["a"], CGSize(width: 400, height: 300))

        // "a" comes on screen while the stack grows (the tool pane went away): only "a" follows it.
        host.rootView = stack(active: "a", sizes)
        window.setContentSize(NSSize(width: 700, height: 300))
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 300)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(sizes.byKey["a"], CGSize(width: 700, height: 300))
        XCTAssertEqual(sizes.byKey["b"], CGSize(width: 400, height: 300))

        // Back on screen, "b" takes the stack's size again.
        host.rootView = stack(active: "b", sizes)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(sizes.byKey["b"], CGSize(width: 700, height: 300))
        XCTAssertEqual(sizes.byKey["a"], CGSize(width: 700, height: 300))
    }

    func testTheSizeOfAPlace() {
        let stack = CGSize(width: 900, height: 600), last = CGSize(width: 600, height: 600)
        XCTAssertEqual(KeepAliveLayout.size(of: KeepAlivePlace(key: "a", active: true), in: stack, last: last), stack)
        XCTAssertEqual(KeepAliveLayout.size(of: KeepAlivePlace(key: "a", active: false), in: stack, last: last), last)
        XCTAssertEqual(KeepAliveLayout.size(of: KeepAlivePlace(key: "a", active: false), in: stack, last: nil), stack)
    }

    func testThePlaceLeavingStaysAwakeUntilSettled() {
        let wake = KeepAliveWake()
        wake.show("chat")
        XCTAssertTrue(wake.isAwake("chat"))
        XCTAssertFalse(wake.isAwake("tasks"))

        wake.show("tasks")
        XCTAssertTrue(wake.isAwake("tasks"))
        XCTAssertTrue(wake.isAwake("chat"), "the place that just left sleeps a frame later")
        // Drawn again with the same place: nothing changes.
        wake.show("tasks")
        XCTAssertEqual(wake.leaving, "chat")

        wake.settle()
        XCTAssertFalse(wake.isAwake("chat"))
        XCTAssertTrue(wake.isAwake("tasks"))
    }

    func testOnlyTheLastPlaceLeftStaysAwake() {
        let wake = KeepAliveWake()
        wake.show("chat"); wake.show("tasks"); wake.show("bugs")
        XCTAssertFalse(wake.isAwake("chat"))
        XCTAssertTrue(wake.isAwake("tasks"))
        XCTAssertTrue(wake.isAwake("bugs"))
        // Everything covered (a mini app on screen): the place it covers sleeps after the frame too.
        wake.show(nil)
        XCTAssertTrue(wake.isAwake("bugs"))
        wake.settle()
        XCTAssertFalse(wake.isAwake("bugs"))
    }
}
