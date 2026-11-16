import AppKit
import CoreUI
import SwiftUI

private struct BoardSearchKey: FocusedValueKey { typealias Value = () -> Void }
private struct BoardRefreshKey: FocusedValueKey { typealias Value = () -> Void }

public extension FocusedValues {
    /// Focuses the search field of the board on screen. Set by `ContextualSearchField` while its section is the active one, so
    /// the menu's ⌘K reaches the board first and falls back to the title bar's search (`ShellModel.searchFocusTick`).
    var boardSearch: (() -> Void)? {
        get { self[BoardSearchKey.self] }
        set { self[BoardSearchKey.self] = newValue }
    }
    /// Refreshes the board on screen. Set by `BoardRefreshButton` while its section is the active one, so the menu's ⌘R
    /// refreshes that board and falls back to syncing the open account.
    var boardRefresh: (() -> Void)? {
        get { self[BoardRefreshKey.self] }
        set { self[BoardRefreshKey.self] = newValue }
    }
}

extension ShellModel {
    /// Esc, offered by the window-level monitor before any view sees it. Closes what is on top and says whether it did:
    /// the detail slide-over, else the host's overlay (the notifications panel). A dialog or an IME composition keeps its Esc.
    func handleEscape() -> Bool {
        if dialogs.isPresenting { return false }
        if nav.openTicketId != nil { nav.closeTicket(); return true }
        return host.dismissOverlay()
    }
}

/// Offers Esc to `ShellModel.handleEscape` for the window it sits in, whichever view has focus (the panel's own focus is lost
/// as soon as the user clicks into a web view or a text field). Popovers and sheets are other windows and are left alone.
struct EscapeKeyMonitor: NSViewRepresentable {
    let handle: () -> Bool

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) { view.handle = handle }

    final class MonitorView: NSView {
        var handle: () -> Bool = { false }
        private var token: Any?

        override func viewDidMoveToWindow() {
            if let token { NSEvent.removeMonitor(token); self.token = nil }
            guard window != nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == 53, event.window === self.window,
                      !((event.window?.firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false) else { return event }
                return self.handle() ? nil : event
            }
        }
        deinit { if let token { NSEvent.removeMonitor(token) } }
    }
}
