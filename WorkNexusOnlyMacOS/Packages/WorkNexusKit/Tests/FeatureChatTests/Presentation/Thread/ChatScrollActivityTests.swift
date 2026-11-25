import AppKit
import CoreUI
@testable import FeatureChat
import SwiftUI
import XCTest

/// While the message list scrolls, nothing in it plays; it all goes on shortly after the list is still.
@MainActor
final class ChatScrollActivityTests: XCTestCase {
    private func eventually(timeout: Double = 2, _ cond: @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testAScrollPutsTheAnimationsToSleepAtOnceAndAStillListWakesThemAfterAMoment() async {
        let activity = ChatScrollActivity()
        XCTAssertTrue(activity.motion.isAwake)

        activity.scrolling(true)
        XCTAssertTrue(activity.isScrolling)
        XCTAssertTrue(activity.shield.on)
        XCTAssertFalse(activity.motion.isAwake, "nothing plays during a scroll")

        activity.scrolling(false, resumeAfter: .milliseconds(60))
        XCTAssertFalse(activity.isScrolling)
        XCTAssertFalse(activity.shield.on, "the pointer finds its row again the moment the list stops")
        XCTAssertFalse(activity.motion.isAwake, "not yet: the wheel may only be between two notches")
        await eventually { activity.motion.isAwake }
        XCTAssertTrue(activity.motion.isAwake)
    }

    func testAScrollThatGoesOnKeepsThemAsleep() async throws {
        let activity = ChatScrollActivity()
        activity.scrolling(true)
        activity.scrolling(false, resumeAfter: .milliseconds(60))
        activity.scrolling(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(activity.motion.isAwake, "the wake-up of the first stop was called off")
    }

    /// What a row reads through `@KeptAwake` is the list's motion inside the chat's own presence: asleep when either is.
    func testTheListsMotionSitsInsideTheChatsPresence() async {
        struct Probe: View {
            @KeptAwake private var awake
            let seen: (Bool) -> Void
            var body: some View { Color.clear.onChange(of: awake, initial: true) { _, now in seen(now) } }
        }
        let chat = KeepAlivePresence(shown: true)
        let activity = ChatScrollActivity()
        var seen: [Bool] = []
        let host = NSHostingView(rootView: Probe { seen.append($0) }.keptAwake(while: activity.motion).environment(chat))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        await eventually { seen == [true] }
        activity.scrolling(true)
        await eventually { seen == [true, false] }
        activity.scrolling(false, resumeAfter: .milliseconds(20))
        await eventually { seen == [true, false, true] }
        chat.show(false)
        await eventually { seen == [true, false, true, false] }
        XCTAssertEqual(seen, [true, false, true, false], "a chat behind another one plays nothing, scrolling or not")
    }
}
