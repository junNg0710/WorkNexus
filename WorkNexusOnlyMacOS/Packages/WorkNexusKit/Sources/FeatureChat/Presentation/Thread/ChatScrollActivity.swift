/// Not in the Flutter app.
import CoreUI
import Observation
import SwiftUI

/// Whether the message list is scrolling, in a plain reference: rows read it in their hover handler, so a scroll starting
/// or stopping redraws nothing.
@MainActor
final class ChatScrollActivity {
    private(set) var isScrolling = false
    /// The sheet over the rows while scrolling; observed by the sheet alone, so the list is not redrawn for it.
    let shield = ScrollShieldState()
    /// How many times the reader has started scrolling by hand (never a scroll the app made).
    var userScrolls = 0
    /// Asleep while the list scrolls: what plays for ever in a row (an animated sticker or picture, the typing dots, a
    /// running ticket's badge) reads it through `@KeptAwake` and holds its frame. Each of those draws on the main thread,
    /// frame by frame, in the very frames the scroll needs. Only they are drawn again when it changes, not the rows.
    let motion = KeepAlivePresence(shown: true)
    private var resume: Task<Void, Never>?

    /// How long the list has to be still before its animations go on: a wheel turned notch by notch stops and starts
    /// many times a second, and each restart is work.
    static let resumeDelay: Duration = .milliseconds(200)

    /// The list started or stopped scrolling.
    func scrolling(_ on: Bool, resumeAfter delay: Duration = ChatScrollActivity.resumeDelay) {
        isScrolling = on
        shield.on = on
        resume?.cancel()
        resume = nil
        if on {
            motion.show(false)
        } else if !motion.isShown {
            resume = Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.motion.show(true)
            }
        }
    }
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
