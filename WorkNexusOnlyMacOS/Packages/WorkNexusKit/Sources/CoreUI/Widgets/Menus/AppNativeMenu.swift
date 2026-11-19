/// Not in the Flutter app.
import AppKit

/// A native menu opened under the pointer from a button. AppKit runs the menu itself until a pick (or Esc), so it stays
/// open whatever the view around the button does meanwhile - unlike a SwiftUI `Menu` in a row whose buttons show only
/// while hovered, which closed (or never opened) as the pointer moved onto the menu.
public enum AppNativeMenu {
    public struct Item {
        public var title: String
        public var icon: String?
        public var destructive: Bool
        public var dividerBefore: Bool
        /// Shown with a check mark (the value picked, a setting that is on).
        public var checked: Bool
        public var enabled: Bool
        /// A submenu instead of an action.
        public var children: [Item]
        public var action: () -> Void
        public init(_ title: String, icon: String? = nil, destructive: Bool = false, dividerBefore: Bool = false,
                    checked: Bool = false, enabled: Bool = true, action: @escaping () -> Void) {
            self.title = title; self.icon = icon; self.destructive = destructive; self.dividerBefore = dividerBefore
            self.checked = checked; self.enabled = enabled; self.children = []; self.action = action
        }

        /// A submenu of `children`.
        public init(_ title: String, icon: String? = nil, dividerBefore: Bool = false, children: [Item]) {
            self.init(title, icon: icon, dividerBefore: dividerBefore, enabled: !children.isEmpty, action: {})
            self.children = children
        }
    }

    /// The menu for `items` (built separately so it can be checked without showing it).
    public static func menu(_ items: [Item]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (i, item) in items.enumerated() {
            if item.dividerBefore, i > 0 { menu.addItem(.separator()) }
            let entry = ClosureItem(title: item.title, run: item.action)
            if let icon = item.icon { entry.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) }
            if item.destructive {
                entry.attributedTitle = NSAttributedString(string: item.title, attributes: [.foregroundColor: NSColor.systemRed])
            }
            entry.state = item.checked ? .on : .off
            entry.isEnabled = item.enabled
            if !item.children.isEmpty { entry.submenu = Self.menu(item.children); entry.action = nil; entry.target = nil }
            menu.addItem(entry)
        }
        return menu
    }

    /// Shows the menu at the pointer and returns once it is closed.
    @MainActor public static func popUp(_ items: [Item]) {
        guard !items.isEmpty else { return }
        menu(items).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Shows the menu just under `view` (from its leading edge); returns once it is closed.
    @MainActor public static func popUp(_ items: [Item], under view: NSView) {
        guard !items.isEmpty else { return }
        let m = menu(items)
        let gap: CGFloat = 4
        let below = NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + gap : -gap)
        m.popUp(positioning: nil, at: below, in: view)
    }

    final class ClosureItem: NSMenuItem {
        let run: () -> Void
        init(title: String, run: @escaping () -> Void) {
            self.run = run
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            target = self
        }
        required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
        @objc func fire() { run() }
    }
}
