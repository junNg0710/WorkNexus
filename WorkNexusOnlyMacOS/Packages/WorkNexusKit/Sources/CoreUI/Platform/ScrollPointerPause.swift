/// Not in the Flutter app.
import AppKit
import QuartzCore

/// Pauses a window's pointer bookkeeping while something in it scrolls.
///
/// Scrolled content moves under a still pointer, so on every frame of a scroll AppKit works out again what the pointer is
/// over — for the cursor, and for which views it has entered or left — and with SwiftUI content that is a hit test
/// through the whole view tree, then a round of hover events. In a long chat it was a fifth of each frame and, with the
/// hover work it set off, the difference between 25 and 58 frames a second on a slow Mac. What the pointer is over does
/// not matter while the content is moving: this turns the bookkeeping off for the scroll and has AppKit catch up once,
/// a moment after the last movement. Until then the cursor and whatever was lit up under the pointer stay as they were.
/// The window cannot be dragged for as long either (see `scrolled(in:now:)`).
///
/// It watches every scroll view of the app (chat, boards, lists, details), by the bounds of their clip views.
@MainActor
public final class ScrollPointerPause {
    public static let shared = ScrollPointerPause()

    /// How long after the last movement a scroll counts as over.
    let settle: TimeInterval
    private var observer: NSObjectProtocol?
    /// The windows paused now, with when each last scrolled.
    private var paused: [ObjectIdentifier: Paused] = [:]

    private struct Paused {
        weak var window: NSWindow?
        var lastMove: CFTimeInterval
        /// A check already found it quiet; the next one that still does ends the pause.
        var seemsOver = false
        /// Whether the window could be moved when the pause began (put back when it ends).
        var wasMovable = true
    }

    /// Run when a window's scrolling is over, after its bookkeeping is back on.
    public var onResume: ((NSWindow) -> Void)?

    init(settle: TimeInterval = 0.15) { self.settle = settle }

    /// Whether something in `window` is scrolling now (its pointer bookkeeping is off).
    public func isPaused(_ window: NSWindow) -> Bool { paused[ObjectIdentifier(window)] != nil }

    /// Starts watching, once.
    public func start() {
        guard observer == nil else { return }
        // Delivered on the thread that moved the view: the main one.
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: nil) { [weak self] note in
            guard Thread.isMainThread, let window = (note.object as? NSClipView)?.window else { return }
            MainActor.assumeIsolated { self?.scrolled(in: window) }
        }
    }

    /// Something scrolled in `window`: its pointer bookkeeping is off until the scrolling has stopped for `settle`.
    func scrolled(in window: NSWindow, now: CFTimeInterval = CACurrentMediaTime()) {
        // A resize moves clip views too, and AppKit manages the cursor itself for its length.
        guard !window.inLiveResize else { return }
        let id = ObjectIdentifier(window)
        if paused[id] != nil {
            paused[id]?.lastMove = now
            paused[id]?.seemsOver = false
            // AppKit turns it back on by itself at times (the window becoming key, for one) in the middle of a scroll.
            if window.areCursorRectsEnabled { window.disableCursorRects() }
            return
        }
        paused[id] = Paused(window: window, lastMove: now, wasMovable: window.isMovable)
        window.disableCursorRects()
        // While a window can be moved, AppKit works out on every frame that changes its content where a press would
        // drag it - a walk through every view, a twentieth of the main thread in a scrolling chat. Nobody drags a
        // window in the middle of a scroll.
        window.isMovable = false
        endHover(in: window)
        checkLater(id, after: settle)
    }

    /// Tells the window's SwiftUI content the pointer has left. Every hover area that moves makes SwiftUI ask again what
    /// is under the pointer once the frame is laid out - and in a scrolling list all of them move on every frame: a tenth
    /// of the main thread in a scrolling chat with the pointer lying still over it (sampled in the installed app; leaving
    /// the mouse moves out did not stop it). With no pointer over the content there is nothing to ask. Whoever listens
    /// for `onResume` brings the pointer back (`PointerMovePace`), as its next real move does anyway.
    private func endHover(in window: NSWindow) {
        guard let content = window.contentView,
              let event = NSEvent.enterExitEvent(with: .mouseExited, location: window.mouseLocationOutsideOfEventStream, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) else { return }
        content.mouseExited(with: event)
    }

    private func checkLater(_ id: ObjectIdentifier, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.resumeIfSettled(id) }
        }
    }

    private func resumeIfSettled(_ id: ObjectIdentifier, now: CFTimeInterval = CACurrentMediaTime()) {
        guard var entry = paused[id] else { return }
        guard let window = entry.window else { paused[id] = nil; return }
        let quiet = now - entry.lastMove
        if quiet < settle { checkLater(id, after: settle - quiet); return }
        // A slow frame holds this check back for as long as it holds the scroll, so "quiet for `settle`" may only mean the
        // main thread was busy: on a slow Mac the pause ended between two frames of a fast scroll, and the bookkeeping it
        // was there to skip ran after all. One more look, once the run loop has had a turn to deliver the scrolling waiting.
        if !entry.seemsOver {
            entry.seemsOver = true
            paused[id] = entry
            checkLater(id, after: settle / 3)
            return
        }
        paused[id] = nil
        if entry.wasMovable { window.isMovable = true }
        window.enableCursorRects()
        // What is under the pointer now: the cursor and the hover of the views there.
        if let content = window.contentView { window.invalidateCursorRects(for: content) }
        onResume?(window)
    }
}
