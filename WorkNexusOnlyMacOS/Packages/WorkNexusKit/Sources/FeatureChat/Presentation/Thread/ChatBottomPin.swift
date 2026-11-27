/// Not in the Flutter app (its list is reversed and grows upwards, so the newest message stays put by itself).
import Foundation

/// Whether the message list is held at its newest message. The scroll view's own bottom anchor works from estimated row
/// heights: a message that comes in and then grows (a link's card, a picture, a date line above it) left the list short of
/// its end, the new message under the input. So while the list was last seen at its end and the reader has not scrolled
/// since, growth under it sends it to the end again.
struct ChatBottomPin {
    /// The list was last seen at its very end, and the reader has not scrolled since.
    private(set) var held = false
    private var touches = 0
    private var content = 0
    private var container = 0

    /// Takes in where the list is now. True when it has to be sent to its end again: it was held there, and it is no
    /// longer because what it shows grew (or its room shrank: the input got taller) - not because anything scrolled it.
    mutating func follows(_ now: ThreadScrollMetrics, userScrolls: Int, scrolling: Bool) -> Bool {
        defer { content = now.contentHeight; container = now.containerHeight }
        if now.atEnd { held = true; touches = userScrolls; return false }
        guard held else { return false }
        let grew = now.contentHeight > content || now.containerHeight < container
        // Scrolled away: by the reader, or by the app (a jump to a message moves the list without it growing).
        guard grew, userScrolls == touches, !scrolling else { held = false; return false }
        return true
    }

    /// The app is taking the list somewhere else (a message jumped to, the reader's row after older messages came in).
    mutating func release() { held = false }
}

/// The latest scroll metrics and the bottom pin, in a plain reference so updating them does not redraw the list.
final class ScrollMemo {
    var metrics = ThreadScrollMetrics()
    var pin = ChatBottomPin()
}

/// The ids of the rows on screen, in a plain reference so changing them does not redraw the list.
final class VisibleRows { var ids: Set<String> = [] }
