import AppKit
import WebKit

/// Listens, for as long as it is started, to the keys and mouse buttons a browser reacts to and hands them to `perform`.
/// A local event monitor sees a key before the menu bar and the page do, so ⌘W and ⌘T are the tabs' and not the window's.
/// Nothing is heard unless the event is for `window()`'s key window.
@MainActor
final class MiniAppKeyMonitor {
    /// Runs the shortcut; true when it did something (the key is then swallowed).
    var perform: (MiniAppShortcut) -> Bool = { _ in false }
    /// The page that mouse back / forward buttons are over, and that the page-editing check asks.
    var web: () -> WKWebView? = { nil }
    private var token: Any?

    var isRunning: Bool { token != nil }

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { [weak self] event in
            nonisolated(unsafe) let pressed = event
            let swallowed = MainActor.assumeIsolated { self?.handle(pressed) ?? false }
            return swallowed ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    deinit { if let token { NSEvent.removeMonitor(token) } }

    /// True when the event was for a browser action and is taken (the page and the menu bar never see it).
    private func handle(_ event: NSEvent) -> Bool {
        guard let page = web(), let window = page.window, event.window === window else { return false }
        if event.type == .otherMouseDown { return mouse(event, page) }
        guard let shortcut = miniAppShortcut(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                                             modifiers: event.modifierFlags) else { return false }
        // ⌥← and ⌥→ move by a word in a text field: in the address field or a text box of the page they are the field's.
        if event.modifierFlags.contains(.option), shortcut == .back || shortcut == .forward {
            if !(window.firstResponder is NSText) { runUnlessEditing(shortcut, in: page) }
            return false
        }
        return perform(shortcut)
    }

    /// Mouse button 4 / 5 (back / forward), over the page.
    private func mouse(_ event: NSEvent, _ page: WKWebView) -> Bool {
        let point = page.convert(event.locationInWindow, from: nil)
        guard page.bounds.contains(point) else { return false }
        switch event.buttonNumber {
        case 3: return perform(.back)
        case 4: return perform(.forward)
        default: return false
        }
    }

    /// The key goes to the page as usual; when nothing editable has the focus there it also moves the history.
    private func runUnlessEditing(_ shortcut: MiniAppShortcut, in page: WKWebView) {
        let script = "(()=>{const e=document.activeElement;return !!e&&(e.isContentEditable||/^(INPUT|TEXTAREA|SELECT)$/.test(e.tagName))})()"
        page.evaluateJavaScript(script) { [weak self] result, _ in
            MainActor.assumeIsolated { if (result as? Bool) != true { _ = self?.perform(shortcut) } }
        }
    }
}
