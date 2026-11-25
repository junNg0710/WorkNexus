import AppKit
import CoreDomain
import CoreUI
import Foundation

/// What a click on a chat of the list took, written to the performance log while it is on: how long the click waited
/// to be handled, how long it was held back (clicks coming faster than chats can be shown), how long the frame that
/// shows the chat took, and when the window stopped being held up by it. A stutter line says a frame was late; this
/// says what the user waited for.
@MainActor
final class ChatClickTiming {
    /// A frame this late (or later) still belongs to showing the chat.
    static let late: TimeInterval = 0.025
    /// Frames are watched this long at most.
    static let watch: TimeInterval = 1.5
    private var clickedAt: TimeInterval?
    private var tappedAt: TimeInterval?
    private var watching: Task<Void, Never>?

    /// The tap reached the list. The event being handled is the release of the mouse button: its stamp is when the
    /// user let go, on the clock the frames are measured on.
    func tapped() {
        guard PerformanceLog.isEnabled else { return }
        let now = PerformanceLog.now()
        tappedAt = now
        clickedAt = NSApp?.currentEvent.flatMap { now - $0.timestamp < 5 ? $0.timestamp : nil } ?? now
    }

    /// The chat is being put on screen; `how`: kept, built ahead, or built now.
    func shown(_ how: String) {
        guard PerformanceLog.isEnabled, let tappedAt, let clickedAt else { return }
        self.tappedAt = nil; self.clickedAt = nil
        let shownAt = PerformanceLog.now()
        watching?.cancel()
        watching = Task {
            await NextDisplayFrame.wait()
            let first = PerformanceLog.now()
            var last = first, settled = first, calm = 0
            while calm < 3, last - first < Self.watch, !Task.isCancelled {
                await NextDisplayFrame.wait()
                let now = PerformanceLog.now()
                if now - last >= Self.late { settled = now; calm = 0 } else { calm += 1 }
                last = now
            }
            guard !Task.isCancelled else { return }
            PerformanceLog.note(Self.line(how, clicked: clickedAt, tapped: tappedAt, shown: shownAt, first: first, settled: settled))
        }
    }

    static func line(_ how: String, clicked: TimeInterval, tapped: TimeInterval, shown: TimeInterval, first: TimeInterval,
                     settled: TimeInterval) -> String {
        func ms(_ t: TimeInterval) -> String { "\(Int((max(0, t) * 1000).rounded())) ms" }
        return "Chat click (\(how)): \(ms(settled - clicked)) until the window was free again - waited \(ms(tapped - clicked)) to be "
            + "handled, held back \(ms(shown - tapped)), first frame \(ms(first - shown)), later frames \(ms(settled - first))"
    }
}
