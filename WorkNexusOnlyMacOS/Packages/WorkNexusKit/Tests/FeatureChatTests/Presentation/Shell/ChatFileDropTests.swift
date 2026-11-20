import AppKit
import CoreDomain
import SwiftUI
import XCTest
@testable import FeatureChat

/// Files dragged from Finder onto an open chat, as AppKit delivers them: on the messages they are sent, on the input they
/// wait above it (never typed in as their paths), and Remove or Esc takes them back.
@MainActor
final class ChatFileDropTests: XCTestCase {
    /// What AppKit hands a drop destination while a drag passes over it.
    @MainActor private final class Drag: NSObject, NSDraggingInfo {
        let draggingPasteboard: NSPasteboard
        let draggingLocation: NSPoint
        weak var window: NSWindow?
        init(at point: NSPoint = .zero, in window: NSWindow? = nil, write: (NSPasteboard) -> Void) {
            draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("wn-drop-\(UUID().uuidString)"))
            draggingPasteboard.clearContents()
            write(draggingPasteboard)
            draggingLocation = point; self.window = window
        }
        convenience init(urls: [URL], at point: NSPoint = .zero, in window: NSWindow? = nil) {
            self.init(at: point, in: window) { _ = $0.writeObjects(urls as [NSURL]) }
        }
        var draggingDestinationWindow: NSWindow? { window }
        var draggingSourceOperationMask: NSDragOperation { .copy }
        var draggedImageLocation: NSPoint { draggingLocation }
        var draggedImage: NSImage? { nil }
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 1 }
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        func resetSpringLoading() {}
    }

    private func tempFile(_ text: String = "release notes") throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wn-drop-\(UUID().uuidString).txt")
        try Data(text.utf8).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return file
    }

    /// The view AppKit gives the drag to at `point` (window coordinates): the frontmost one there registered for drags.
    private func destination(_ window: NSWindow, at point: NSPoint) -> NSView? {
        var found: NSView?
        func walk(_ v: NSView) {
            if !v.registeredDraggedTypes.isEmpty, v.convert(v.bounds, to: nil).contains(point) { found = v }
            v.subviews.forEach(walk)
        }
        if let root = window.contentView { walk(root) }
        return found
    }

    private func drop(_ url: URL, at point: NSPoint, in window: NSWindow) -> Bool {
        guard let dest = destination(window, at: point) else { return false }
        let drag = Drag(urls: [url], at: point, in: window)
        guard dest.draggingEntered(drag) != [] else { dest.draggingExited(drag); return false }
        _ = dest.draggingUpdated(drag)
        return dest.prepareForDragOperation(drag) && dest.performDragOperation(drag)
    }

    // MARK: the input

    /// The input is a text view, which on its own takes a dropped file as text and types its path in.
    func testAFileDroppedOnTheInputIsHandedOverNotTyped() throws {
        let view = ComposerNSTextView()
        var dropped: [NSPasteboard] = []
        view.onDropFiles = { dropped.append($0); return true }
        let drag = Drag(urls: [try tempFile()])
        XCTAssertEqual(view.draggingEntered(drag), .copy)
        XCTAssertTrue(view.prepareForDragOperation(drag))
        XCTAssertTrue(view.performDragOperation(drag))
        view.concludeDragOperation(drag)
        XCTAssertEqual(dropped.count, 1)
        XCTAssertEqual(view.string, "", "no path typed into the input")
    }

    func testDraggedTextIsLeftToTheInput() {
        let view = ComposerNSTextView()
        var dropped = 0
        view.onDropFiles = { _ in dropped += 1; return true }
        let drag = Drag { $0.setString("hello", forType: .string) }
        XCTAssertFalse(ComposerNSTextView.carriesFiles(drag.draggingPasteboard))
        _ = view.performDragOperation(drag)
        XCTAssertEqual(dropped, 0)
    }

    /// Dropped on the input, files wait above it; Remove, or Esc, takes them all back and nothing is sent.
    func testFilesDroppedOnTheInputWaitAndCanBeRemoved() throws {
        let state = ChatThreadState(accountId: "a", chat: ShellMake.chat("drop-\(UUID().uuidString)"))
        let controller = ChatComposerController(state: state)
        let one = try tempFile("one"), two = try tempFile("two")
        XCTAssertTrue(controller.dropAttachments(Drag(urls: [one, two]).draggingPasteboard))
        XCTAssertEqual(state.stagedFiles.map(\.name), [one.lastPathComponent, two.lastPathComponent])
        XCTAssertEqual(controller.model.text, "")

        controller.removeStaged(state.stagedFiles[0].id)
        XCTAssertEqual(state.stagedFiles.map(\.name), [two.lastPathComponent])
        controller.clearStaged()
        XCTAssertTrue(state.stagedFiles.isEmpty)

        XCTAssertTrue(controller.dropAttachments(Drag(urls: [one]).draggingPasteboard))
        XCTAssertTrue(controller.handle(.escape))
        XCTAssertTrue(state.stagedFiles.isEmpty)
    }

    func testAChatSelectingMessagesTakesNoDrop() throws {
        let state = ChatThreadState(accountId: "a", chat: ShellMake.chat("drop-\(UUID().uuidString)"))
        state.beginSelection(with: Make.message("m1", chat: state.chatGid, sender: 2, content: .text("hi"), serverId: 5))
        let controller = ChatComposerController(state: state)
        XCTAssertFalse(controller.dropAttachments(Drag(urls: [try tempFile()]).draggingPasteboard))
        XCTAssertTrue(state.stagedFiles.isEmpty)
    }

    // MARK: the messages

    func testAFileDroppedOnTheMessagesIsSent() async throws {
        let repo = ShellFakeRepository()
        let account = Account(id: "a", workspaceId: "w", providerType: .zentao, handle: "me")
        let events = ChatShellEvents()
        let root = ChatRootView(account: account, events: events).chatServices(ChatServices(chat: repo)).frame(width: 1100, height: 700)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host; window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        await ShellMake.expectEventually { repo.conversationsCont != nil && repo.usersCont != nil && repo.statusCont != nil }
        repo.statusCont?.yield(.online(selfUserId: 1))
        repo.usersCont?.yield([ShellMake.user(1, "Me", account: "me"), ShellMake.user(2, "An")])
        var group = ShellMake.chat("g", name: "Release Team", at: Make.t0.timeIntervalSince1970); group.ownerAccount = "me"
        repo.conversationsCont?.yield([group])
        events.open(chatGid: "g")
        for _ in 0..<8 { try await Task.sleep(for: .milliseconds(40)); host.layoutSubtreeIfNeeded() }

        let file = try tempFile()
        // The middle of the messages (window coordinates, origin bottom-left), right of the chat list.
        XCTAssertTrue(drop(file, at: NSPoint(x: 800, y: 400), in: window), "the messages take a dropped file")
        await ShellMake.expectEventually { !repo.sentFiles.isEmpty }
        XCTAssertEqual(repo.sentFiles, ["g/\(file.lastPathComponent)"])
    }
}
