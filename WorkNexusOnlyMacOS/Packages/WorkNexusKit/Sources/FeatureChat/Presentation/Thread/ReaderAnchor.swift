/// Not in the Flutter app.
import Foundation

/// The row that keeps the reader's place while older messages are added above it: put back at the top of the list once
/// they are in.
enum ReaderAnchor {
    /// The first message on screen. Never the day or time line above it: that line belongs to the day's first message,
    /// so once older messages of the same day are in it sits above them - and putting it back at the top threw the
    /// reader to the start of the new page, past every message just loaded.
    static func row(_ rows: [ChatListRow], visible: Set<String>) -> String? {
        rows.first { $0.item.message != nil && visible.contains($0.id) }?.id
    }

    /// Whether the list was left above the row `id` after older rows came in: it is not on screen, and what is on screen
    /// comes before it. (Below it, the reader scrolled on by themself: nothing to put back.)
    static func isLost(_ id: String, rows: [ChatListRow], visible: Set<String>) -> Bool {
        guard !visible.contains(id), let at = rows.firstIndex(where: { $0.id == id }),
              let top = rows.firstIndex(where: { visible.contains($0.id) }) else { return false }
        return top < at
    }
}
