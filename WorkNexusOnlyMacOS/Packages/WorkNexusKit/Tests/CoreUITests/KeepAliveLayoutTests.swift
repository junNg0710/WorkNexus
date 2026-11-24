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

    func testOnlyTheViewShownIsAwake() {
        let wake = KeepAliveWake()
        wake.prepare(shown: "chat", keys: ["chat", "tasks"], around: nil)
        let chat = wake.presence("chat"), tasks = wake.presence("tasks")
        XCTAssertTrue(chat.isAwake, "built as the view on screen")
        XCTAssertFalse(tasks.isAwake)
        XCTAssertTrue(wake.presence("chat") === chat, "one presence per view, never replaced")

        // The stack is drawn with another view: the presences change after it, in `show`.
        wake.prepare(shown: "tasks", keys: ["chat", "tasks"], around: nil)
        XCTAssertTrue(chat.isAwake)
        wake.show("tasks")
        XCTAssertFalse(chat.isAwake)
        XCTAssertTrue(tasks.isAwake)

        // Everything covered (a mini app on screen): no view is awake.
        wake.show(nil)
        XCTAssertFalse(tasks.isAwake)
        XCTAssertFalse(wake.isAwake("tasks"))
    }

    func testAViewBuiltLaterStartsAsWhatItIs() {
        let wake = KeepAliveWake()
        wake.prepare(shown: "chat", keys: ["chat"], around: nil)
        _ = wake.presence("chat")
        wake.prepare(shown: "bugs", keys: ["chat", "bugs"], around: nil)
        XCTAssertTrue(wake.presence("bugs").isAwake, "awake from its first frame")
        wake.show("bugs")
        XCTAssertFalse(wake.isAwake("chat"))
    }

    func testAViewNoLongerKeptIsForgotten() {
        let wake = KeepAliveWake()
        wake.prepare(shown: "a", keys: ["a", "b"], around: nil)
        let old = wake.presence("b")
        wake.prepare(shown: "a", keys: ["a"], around: nil)
        wake.prepare(shown: "a", keys: ["a", "b"], around: nil)
        XCTAssertFalse(wake.presence("b") === old, "kept again later: a new view, a new presence")
    }

    func testAKeptViewInsideAHiddenOneIsAsleep() {
        let place = KeepAlivePresence(shown: true)
        let wake = KeepAliveWake()
        wake.prepare(shown: "chat1", keys: ["chat1"], around: place)
        let chat = wake.presence("chat1")
        XCTAssertTrue(chat.isAwake)
        // The chat place goes behind another place: its open chat is not on screen either.
        let outer = KeepAliveWake()
        outer.prepare(shown: "chat", keys: ["chat", "tasks"], around: nil)
        let chatPlace = outer.presence("chat")
        let inner = KeepAliveWake()
        inner.prepare(shown: "c", keys: ["c"], around: chatPlace)
        let thread = inner.presence("c")
        XCTAssertTrue(thread.isAwake)
        outer.show("tasks")
        XCTAssertFalse(thread.isAwake)
        XCTAssertTrue(thread.isShown, "still the chat its own stack shows")
        outer.show("chat")
        XCTAssertTrue(thread.isAwake)
    }
}
