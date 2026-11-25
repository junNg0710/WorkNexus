import AppKit
import CoreGraphics
import Foundation

/// Chats built ahead of a visit. Opening a chat builds its header, input and a screenful of messages - on a real account
/// some 150 ms over three or four late frames - where going to a chat already built costs a fraction of that. So while
/// nobody is typing, scrolling or clicking, the chats most likely to be opened next are built behind the one on screen,
/// one at a time: the unread ones first, then down the list.
extension ChatShellModel {
    /// How many chats are kept built ahead of a visit at a time.
    static let warmAhead = 3
    /// How long the list is left alone after a chat is picked (and between two chats built).
    static var warmPause: Duration = .milliseconds(1500)
    /// How long the keyboard, the wheel and the buttons must have been still.
    static let warmQuiet: TimeInterval = 0.8

    /// The chat to build next: unread ones first, then in the order of the list; none while the user is searching the
    /// list, or when enough are built ahead already.
    var nextToWarm: String? {
        guard !isSearching, openThreads.count < Self.openThreadLimit,
              openThreads.filter({ !$0.wasOpened }).count < Self.warmAhead else { return nil }
        let kept = Set(openThreads.map(\.state.chatGid))
        let chats = listed.map(\.chat).filter { !kept.contains($0.gid) }
        return (chats.first { $0.unreadCount > 0 } ?? chats.first)?.gid
    }

    /// Starts over after each chat picked: the chats are built only once the user has stopped.
    func scheduleWarming(isQuiet: @escaping @MainActor () -> Bool = { UserQuiet.forAtLeast(ChatShellModel.warmQuiet) }) {
        warming?.cancel()
        warming = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.warmPause)
                guard let self, !Task.isCancelled else { return }
                guard isQuiet() else { continue }
                guard let gid = nextToWarm, warm(gid) else { return }
            }
        }
    }
}

/// Whether the user has left the keyboard, the wheel and the mouse buttons alone for a while (moving the pointer does
/// not count: building a chat behind the one being read is not seen then) - or is working in another app.
@MainActor
enum UserQuiet {
    static func forAtLeast(_ seconds: TimeInterval) -> Bool {
        guard NSApp?.isActive ?? false else { return true }
        let kinds: [CGEventType] = [.keyDown, .scrollWheel, .leftMouseDown, .leftMouseDragged, .rightMouseDown]
        return kinds.allSatisfy { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) >= seconds }
    }
}
