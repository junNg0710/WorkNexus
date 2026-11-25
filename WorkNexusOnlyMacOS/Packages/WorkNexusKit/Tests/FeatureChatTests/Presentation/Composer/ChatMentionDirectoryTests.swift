import AppKit
import CoreDomain
import SwiftUI
import XCTest
@testable import FeatureChat

@MainActor
final class ChatMentionDirectoryTests: XCTestCase {
    private final class Members: StubChatRepository, @unchecked Sendable {
        let fetched = XCTestExpectation(description: "The composer requested this group's members")
        override func members(accountId: String, chatGid: String) async -> Outcome<[Int]> {
            fetched.fulfill()
            return .success([1, 12])
        }
    }

    private func editor(in view: NSView) -> ComposerNSTextView? {
        if let input = view as? ComposerNSTextView { return input }
        for child in view.subviews {
            if let input = editor(in: child) { return input }
        }
        return nil
    }

    func testDirectoryArrivalMakesNameSelectableWithoutRetyping() async throws {
        let state = ChatThreadState(accountId: "a", chat: ShellMake.chat(UUID().uuidString))
        state.selfUserId = 1
        var settings = ChatSettings()
        settings.sendTypingStatus = false
        let repo = Members()
        let host = NSHostingView(rootView: ChatComposerView(state: state)
            .environment(\.chatServices, ChatServices(chat: repo)).environment(\.chatSettings, settings))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let input = try XCTUnwrap(editor(in: host))
        input.insertText("@duong", replacementRange: NSRange(location: 0, length: 0))
        await fulfillment(of: [repo.fetched], timeout: 3)
        XCTAssertFalse(input.onKey?(.tab) ?? false)
        state.users[12] = ChatUser(accountId: "a", userId: 12, account: "twelve", realname: "Đường")
        await ShellMake.expectEventually { input.onKey?(.tab) == true }
        await ShellMake.expectEventually { input.string == "@Đường " }
    }
}
