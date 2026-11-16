import AppKit
import SwiftUI

/// Makes the view behind it drag the window and zoom it on double-click, like a native title bar
/// (the window has a hidden title bar, so the system gives us no drag region of our own).
public struct WindowDragArea: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> DragView { DragView() }
    public func updateNSView(_ nsView: DragView, context: Context) {}

    public final class DragView: NSView {
        public override var mouseDownCanMoveWindow: Bool { true }
        public override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
                if action == "Minimize" { window?.miniaturize(nil) } else if action != "None" { window?.zoom(nil) }
            } else { super.mouseDown(with: event) }
        }
    }
}
