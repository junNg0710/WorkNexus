import AppKit
import SwiftUI

/// Hidden title bar; the traffic lights sit on the floating glass sidebar (macos/Runner/MainFlutterWindow.swift).
/// Hands the window to `onWindow` once (tray + placement recorder).
struct WindowConfigurator: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void = { _ in }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            Self.configure(v.window)
            if let w = v.window { onWindow(w) }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { Self.configure(nsView.window) }

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
