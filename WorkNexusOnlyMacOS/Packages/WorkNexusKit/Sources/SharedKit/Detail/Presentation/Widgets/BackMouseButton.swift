import AppKit
import SwiftUI

/// Ported from: lib/shared/detail/presentation/detail_overlay.dart (`kBackMouseButton` listener)
/// Turns the mouse's "back" side button (button 3) pressed over the view into `action`, like ⌘[ — the Dart overlay
/// listened for `kBackMouseButton` on each detail panel.
enum BackMouseButton {
    /// AppKit numbers the side buttons 3 (back) and 4 (forward).
    static let buttonNumber = 3
    static func isBack(_ buttonNumber: Int) -> Bool { buttonNumber == Self.buttonNumber }
}

private struct BackMouseButtonMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) { view.action = action }

    final class MonitorView: NSView {
        var action: () -> Void = {}
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
                guard let self, BackMouseButton.isBack(event.buttonNumber), event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.action()
                return nil
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

extension View {
    /// Calls `action` when the mouse's back button is pressed over this view (only while `enabled`).
    func onBackMouseButton(enabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        background { if enabled { BackMouseButtonMonitor(action: action) } }
    }
}
