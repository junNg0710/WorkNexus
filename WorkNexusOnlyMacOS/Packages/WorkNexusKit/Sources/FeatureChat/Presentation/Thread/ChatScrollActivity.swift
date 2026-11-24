/// Not in the Flutter app.
import Observation
import SwiftUI

/// Whether the message list is scrolling, in a plain reference: rows read it in their hover handler, so a scroll starting
/// or stopping redraws nothing.
final class ChatScrollActivity {
    var isScrolling = false
    /// The sheet over the rows while scrolling; observed by the sheet alone, so the list is not redrawn for it.
    let shield = ScrollShieldState()
    /// How many times the reader has started scrolling by hand (never a scroll the app made).
    var userScrolls = 0
}

private struct ChatScrollActivityKey: EnvironmentKey { static let defaultValue: ChatScrollActivity? = nil }
extension EnvironmentValues {
    var chatScrollActivity: ChatScrollActivity? {
        get { self[ChatScrollActivityKey.self] }
        set { self[ChatScrollActivityKey.self] = newValue }
    }
}

/// Whether the list is scrolling, for `ScrollHoverShield` to observe.
@Observable final class ScrollShieldState { var on = false }

/// A clear, hit-testable sheet over the rows while the list scrolls: the pointer is "over the sheet", so nothing asks
/// each row whether it is under it. Gone the moment the scroll stops, when the row under the pointer is found once.
struct ScrollHoverShield: View {
    let activity: ChatScrollActivity
    var body: some View {
        if activity.shield.on { Color.clear.contentShape(Rectangle()) }
    }
}
