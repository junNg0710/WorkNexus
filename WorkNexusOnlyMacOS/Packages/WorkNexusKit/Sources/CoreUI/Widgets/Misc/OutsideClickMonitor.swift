import AppKit
import SwiftUI

/// Ported from: Flutter's `TapRegion` / `onTapOutside` as the search results popover uses it.
/// Calls `perform` when the mouse goes down outside the view it modifies and outside `extra` (a rect in the view's own
/// top-left coordinates for what it shows beside itself, e.g. a popover under it). The click still reaches what was
/// clicked: this only listens. Active only while `isActive`.
public extension View {
    func onOutsideClick(isActive: Bool, extra: CGRect = .null, perform: @escaping () -> Void) -> some View {
        background(OutsideClickMonitor(isActive: isActive, extra: extra, perform: perform))
    }
}

private struct OutsideClickMonitor: NSViewRepresentable {
    let isActive: Bool
    let extra: CGRect
    let perform: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.extra = extra
        view.perform = perform
        view.setActive(isActive)
    }

    final class MonitorView: NSView {
        var extra = CGRect.null
        var perform: (() -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func setActive(_ on: Bool) {
            if on, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self, event.window === self.window else { return event }
                    let p = self.convert(event.locationInWindow, from: nil)
                    if !self.bounds.contains(p), !self.extra.contains(p) { DispatchQueue.main.async { self.perform?() } }
                    return event
                }
            } else if !on, let monitor {
                NSEvent.removeMonitor(monitor); self.monitor = nil
            }
        }

        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { setActive(false) } }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
