/// Ported from: lib/features/chat/presentation/providers/chat_message_window.dart
import Foundation

/// Which of a chat's messages the thread shows.
enum ChatMessageWindow: Hashable {
    /// The newest `limit` messages of the timeline; `limit` grows as older pages load.
    case live(limit: Int)
    /// A stretch far back in the chat, around a message jumped to: the messages with an index in `from`...`to`, growing
    /// either way as the user scrolls.
    case around(from: Int, to: Int)

    /// How many messages one page adds (`ChatController.pageSize`).
    static let pageSize = 50
    static let initial = ChatMessageWindow.live(limit: pageSize)

    var isAround: Bool { if case .around = self { true } else { false } }

    /// The window after `count` older messages joined it.
    func growingOlder(shown: Int, by count: Int) -> ChatMessageWindow {
        switch self {
        case .live: .live(limit: shown + count)
        case .around(let from, let to): .around(from: from - count, to: to)
        }
    }

    /// The window after `count` newer messages joined it (only a jump window grows downwards).
    func growingNewer(by count: Int) -> ChatMessageWindow {
        if case .around(let from, let to) = self { .around(from: from, to: to + count) } else { self }
    }

    /// The window around the message at `index`: 25 either side (`from` never below the first message).
    static func around(index: Int) -> ChatMessageWindow { .around(from: max(1, index - 25), to: index + 25) }
}
