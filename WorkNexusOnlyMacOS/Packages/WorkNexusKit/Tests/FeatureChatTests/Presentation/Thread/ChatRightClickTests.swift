import AppKit
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureChat

/// A right-click in a chat's message list always gets the app's menu: the message's text menu on its text, its whole
/// menu elsewhere on it, and copying on text no message answered for.
@MainActor
final class ChatRightClickTests: XCTestCase {
    private func window() throws -> (NSWindow, NSHostingView<some View>) {
        let view = VStack(alignment: .leading, spacing: 40) {
            Text("A message the user can select").textSelection(.enabled)
            Text("Its translation, selectable too").textSelection(.enabled)
        }
        .padding(20).frame(width: 400, height: 200, alignment: .topLeading)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let w = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        return (w, host)
    }

    private func titles(_ items: [AppNativeMenu.Item]?) -> [String]? { items?.map(\.title) }

    func testTheMessageUnderThePointerAnswersOnTextAndElsewhere() async throws {
        let (w, host) = try window()
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let row = MessageTextRightClick.CatcherView(frame: host.bounds)
        host.addSubview(row)
        row.items = { _, onText in [AppNativeMenu.Item(onText ? "text menu" : "whole menu") {}] }
        ChatRightClick.shared.add(row); defer { ChatRightClick.shared.remove(row) }
        // On the message's text and on its translation's: the text menu. On the bubble around them: the whole menu.
        XCTAssertEqual(titles(ChatRightClick.shared.menu(at: NSPoint(x: 40, y: 200 - 28), in: w)), ["text menu"])
        XCTAssertEqual(titles(ChatRightClick.shared.menu(at: NSPoint(x: 40, y: 200 - 84), in: w)), ["text menu"])
        XCTAssertEqual(titles(ChatRightClick.shared.menu(at: NSPoint(x: 380, y: 10), in: w)), ["whole menu"])
    }

    func testTextNoMessageAnsweredForOffersCopying() async throws {
        let (w, host) = try window()
        try await Task.sleep(for: .milliseconds(200))
        let area = MessageListRightClick.AreaView(frame: host.bounds)
        host.addSubview(area)
        ChatRightClick.shared.addArea(area); defer { ChatRightClick.shared.removeArea(area) }
        XCTAssertEqual(titles(ChatRightClick.shared.menu(at: NSPoint(x: 40, y: 200 - 28), in: w)), ["Copy text"])
        XCTAssertNil(ChatRightClick.shared.menu(at: NSPoint(x: 380, y: 10), in: w), "not on text: the click is left alone")
    }
}
