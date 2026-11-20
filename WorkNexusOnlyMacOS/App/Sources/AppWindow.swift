import AppKit
import CoreUI
import SwiftUI

/// Hidden title bar; the traffic lights sit on the floating glass sidebar (macos/Runner/MainFlutterWindow.swift).
/// Hands the window to `onWindow` once (tray + placement recorder).
struct WindowConfigurator: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void = { _ in }

    func makeCoordinator() -> TrafficLightKeeper { TrafficLightKeeper() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let keeper = context.coordinator
        DispatchQueue.main.async {
            Self.configure(v.window)
            // Scrolling anywhere in the app is not slowed by the pointer lying over what scrolls.
            ScrollPointerPause.shared.start()
            if let w = v.window { keeper.watch(w); onWindow(w) }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { Self.configure(nsView.window) }

    /// Puts the traffic lights back on the sidebar whenever macOS lays the title bar out again: a resize, leaving full
    /// screen, a new screen or appearance put them back at their default place, across the sidebar's rounded corner.
    @MainActor final class TrafficLightKeeper {
        private var observers: [NSObjectProtocol] = []
        private weak var window: NSWindow?

        func watch(_ w: NSWindow) {
            guard window !== w else { return }
            observers.forEach(NotificationCenter.default.removeObserver)
            window = w
            let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                              NSWindow.didExitFullScreenNotification, NSWindow.didChangeScreenNotification,
                                              NSWindow.didChangeBackingPropertiesNotification, NSWindow.didBecomeKeyNotification]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak w] _ in
                    // After AppKit's own layout of the title bar for this change.
                    DispatchQueue.main.async { MainActor.assumeIsolated { WindowConfigurator.configure(w) } }
                }
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }

    static func configure(_ w: NSWindow?) {
        guard let w else { return }
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.titlebarSeparatorStyle = .none
        w.styleMask.insert(.fullSizeContentView)
        w.isMovableByWindowBackground = false
        w.minSize = NSSize(width: 680, height: 480)
        let titleBar: CGFloat = 60
        for (i, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let b = w.standardWindowButton(kind), let container = b.superview?.superview else { continue }
            container.setFrameSize(NSSize(width: container.frame.width, height: titleBar))
            container.setFrameOrigin(NSPoint(x: container.frame.origin.x, y: w.frame.height - titleBar))
            b.setFrameOrigin(NSPoint(x: 24 + CGFloat(i) * 20, y: (titleBar - b.frame.height) / 2))
        }
    }
}
