import AppKit
@testable import CoreUI
import SwiftUI
import XCTest

/// The arrival veil plays when its trigger changes, and only then.
@MainActor
final class ContentArrivalTests: XCTestCase {
    private final class Box: ObservableObject { @Published var key = "a"; @Published var enabled = true }

    private struct Probe: View {
        @ObservedObject var box: Box
        var body: some View {
            Color.red.contentArrival(on: box.key, backdrop: .white, enabled: box.enabled)
        }
    }

    private func mount(_ box: Box, reduceMotion: Bool = false) -> (NSWindow, NSView) {
        let host = NSHostingView(rootView: Probe(box: box).environment(\._accessibilityReduceMotion, reduceMotion))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    private func veil(in view: NSView) -> ArrivalVeilView? {
        if let found = view as? ArrivalVeilView { return found }
        for child in view.subviews { if let found = veil(in: child) { return found } }
        return nil
    }

    private func settle(_ host: NSView) async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(30))
        host.layoutSubtreeIfNeeded()
    }

    func testTheVeilIsClearAtRestAndPlaysWhenTheTriggerChanges() async throws {
        let box = Box()
        let (window, host) = mount(box)
        defer { window.orderOut(nil) }
        await settle(host)
        let veil = try XCTUnwrap(veil(in: host))
        XCTAssertEqual(veil.layer?.opacity, 0)
        XCTAssertEqual(veil.frame.size, CGSize(width: 200, height: 120), "it covers the content")
        XCTAssertNil(veil.layer?.animation(forKey: "arrival"), "what the content was built with is not an arrival")

        box.key = "b"
        await settle(host)
        let fade = try XCTUnwrap(veil.layer?.animation(forKey: "arrival") as? CABasicAnimation)
        XCTAssertEqual(fade.fromValue as? Float, ArrivalVeilView.strength)
        XCTAssertEqual(fade.toValue as? Float, 0)
        XCTAssertEqual(veil.layer?.opacity, 0, "at rest the veil stays clear: the animation only passes over it")
    }

    func testTheVeilLetsClicksThrough() async throws {
        let (window, host) = mount(Box())
        defer { window.orderOut(nil) }
        await settle(host)
        let veil = try XCTUnwrap(veil(in: host))
        XCTAssertNil(veil.hitTest(NSPoint(x: veil.frame.midX, y: veil.frame.midY)))
    }

    func testNothingPlaysWhenDisabledOrWithReducedMotion() async throws {
        let off = Box(); off.enabled = false
        let (window, host) = mount(off)
        defer { window.orderOut(nil) }
        await settle(host)
        off.key = "b"
        await settle(host)
        XCTAssertNil(try XCTUnwrap(veil(in: host)).layer?.animation(forKey: "arrival"))

        let calm = Box()
        let (calmWindow, calmHost) = mount(calm, reduceMotion: true)
        defer { calmWindow.orderOut(nil) }
        await settle(calmHost)
        calm.key = "b"
        await settle(calmHost)
        XCTAssertNil(try XCTUnwrap(veil(in: calmHost)).layer?.animation(forKey: "arrival"))
    }
}
