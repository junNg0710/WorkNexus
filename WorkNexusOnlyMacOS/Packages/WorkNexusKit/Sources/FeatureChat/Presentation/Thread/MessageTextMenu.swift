/// Not in the Flutter app.
import AppKit
import CoreUI
import SwiftUI

extension ThreadContext {
    /// What a right-click on a message's text offers, instead of the text system's menu (Font, Spelling, Writing Direction,
    /// Services…): copy the words picked, copy the message, reply, forward, translate. The rest stays under "…".
    func textMenu(for message: ChatMessage, settings: ChatSettings, selection: String?) -> [AppNativeMenu.Item] {
        var items: [AppNativeMenu.Item] = []
        if let selection, !selection.isEmpty {
            items.append(AppNativeMenu.Item(L.copySelection, icon: "text.cursor") { Self.copy(selection) })
        }
        let wanted = ["copy", "reply", "forward", "translate", "retranslate", "translateTo"]
        let actions = actions(for: message, settings: settings, inThread: false).filter { wanted.contains($0.id) }
            .sorted { wanted.firstIndex(of: $0.id)! < wanted.firstIndex(of: $1.id)! }
        for (i, a) in actions.enumerated() {
            items.append(a.nativeMenuItem(dividerBefore: i == 0 || a.id == "reply"))
        }
        return items
    }
}

extension MessageAction {
    /// The action as a native menu item, its children as a submenu.
    func nativeMenuItem(dividerBefore: Bool = false) -> AppNativeMenu.Item {
        children.isEmpty
            ? AppNativeMenu.Item(title, icon: icon, destructive: destructive, dividerBefore: dividerBefore, action: run)
            : AppNativeMenu.Item(title, icon: icon, dividerBefore: dividerBefore, children: children.map { $0.nativeMenuItem() })
    }
}

/// Answers a right-click on the text inside the view it is put behind with `items` (given the words picked there, if
/// any). Watches only while `active` (the pointer is over the message); a right-click anywhere else keeps its own menu.
struct MessageTextRightClick: NSViewRepresentable {
    let active: Bool
    let items: (_ selection: String?) -> [AppNativeMenu.Item]

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.items = items
        view.setActive(active)
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.setActive(false) }

    final class CatcherView: NSView {
        var items: ((String?) -> [AppNativeMenu.Item])?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func setActive(_ on: Bool) {
            if on, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                    guard let self, let window, event.window === window,
                          bounds.contains(convert(event.locationInWindow, from: nil)),
                          let text = Self.textView(at: event.locationInWindow, in: window),
                          let items = items?(Self.selection(of: text)), !items.isEmpty else { return event }
                    AppNativeMenu.popUp(items)
                    return nil
                }
            } else if !on, let m = monitor {
                NSEvent.removeMonitor(m); monitor = nil
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        /// The view of the text under the pointer, if it is on text: selectable SwiftUI text is drawn by a private AppKit view
        /// that reads as static text to accessibility (an `NSTextView` elsewhere).
        private static func textView(at point: NSPoint, in window: NSWindow) -> NSView? {
            guard let content = window.contentView else { return nil }
            var view = content.hitTest(content.convert(point, from: nil))
            while let v = view {
                if v is NSTextView || v.accessibilityRole() == .staticText { return v }
                view = v.superview
            }
            return nil
        }

        /// The words picked in it, if any.
        private static func selection(of view: NSView) -> String? {
            if let text = view as? NSTextView {
                let string = text.string as NSString
                let picked = text.selectedRanges.map(\.rangeValue).filter { $0.length > 0 && NSMaxRange($0) <= string.length }
                return picked.isEmpty ? nil : picked.map { string.substring(with: $0) }.joined(separator: "\n")
            }
            return view.accessibilitySelectedText().flatMap { $0.isEmpty ? nil : $0 }
        }
    }
}
