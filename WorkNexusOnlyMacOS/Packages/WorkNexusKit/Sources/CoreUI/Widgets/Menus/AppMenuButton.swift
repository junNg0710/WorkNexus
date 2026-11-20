/// Not in the Flutter app.
import AppKit
import SwiftUI

/// A button that opens a native menu under itself: the app's dropdowns and "…" buttons.
///
/// A SwiftUI `Menu` lives inside the view tree, so whatever redraws the views around it while it is open — a hover
/// handler, a panel sliding, a chat message or presence update arriving — could close it, or swallow the pick, which made
/// dropdowns all over the app "not take a click". AppKit runs this menu itself until a pick or Esc, whatever the views do
/// meanwhile. `items` is read when the menu opens, so it always shows the current state.
///
/// The mouse opens it on the press, from an AppKit view over the label (`appMenu`), as every native pull-down does; the
/// SwiftUI button underneath is what the keyboard and accessibility press.
public struct AppMenuButton<Label: View>: View {
    let items: () -> [AppNativeMenu.Item]
    let help: String?
    let label: Label
    @State private var anchor = AppMenuAnchor()

    public init(help: String? = nil, items: @escaping () -> [AppNativeMenu.Item], @ViewBuilder label: () -> Label) {
        self.items = items; self.help = help; self.label = label()
    }

    public var body: some View {
        Button {
            AppNativeMenu.popUp(items(), under: anchor)
        } label: { label.contentShape(Rectangle()) }
        .buttonStyle(.plain)
        .help(help ?? "")
        .accessibilityAddTraits(.isButton)
        .appMenu(anchor, help: help, items: items)
    }
}

/// Where a button's menu is shown from: the AppKit view over it (`appMenu`).
@MainActor public final class AppMenuAnchor {
    weak var view: NSView?
    public init() {}
}

public extension View {
    /// Makes a press of the mouse on this view open `items` as a native menu just under it, and marks it as where
    /// `anchor`'s menu opens when something else asks (`AppNativeMenu.popUp(_:under:)`: the keyboard, accessibility).
    ///
    /// The menu starts on the press, in AppKit's own mouse handling: opened later, from a SwiftUI button's action (the
    /// release), a menu in the window's title area closed again the moment it appeared. A press, a drag to an item and a
    /// release picks it, as in any pull-down. `onOpenChange` says when it opens and when it has closed.
    func appMenu(_ anchor: AppMenuAnchor, help: String? = nil, onOpenChange: ((Bool) -> Void)? = nil,
                 items: @escaping () -> [AppNativeMenu.Item]) -> some View {
        overlay(MenuPressView(anchor: anchor, help: help, items: items, onOpenChange: onOpenChange))
    }
}

public extension AppNativeMenu {
    /// Shows the menu just under the view `anchor` marks; under the pointer only when that view is not there.
    @MainActor static func popUp(_ items: [Item], under anchor: AppMenuAnchor) {
        if let view = anchor.view { popUp(items, under: view) } else { popUp(items) }
    }
}

private struct MenuPressView: NSViewRepresentable {
    let anchor: AppMenuAnchor
    let help: String?
    let items: () -> [AppNativeMenu.Item]
    let onOpenChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> PressView {
        let v = PressView()
        update(v)
        return v
    }
    func updateNSView(_ view: PressView, context: Context) { update(view) }

    private func update(_ v: PressView) {
        anchor.view = v
        v.items = items; v.onOpenChange = onOpenChange
        v.toolTip = (help ?? "").isEmpty ? nil : help
    }

    /// Takes the press and runs the menu from it. Top-left origin, so "just below" is the view's height.
    final class PressView: NSView {
        var items: () -> [AppNativeMenu.Item] = { [] }
        var onOpenChange: ((Bool) -> Void)?
        private var open = false

        override var isFlipped: Bool { true }
        /// A press here is for the menu, wherever the button stands (the window's title area drags the window).
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard !open else { return }
            let list = items()
            guard !list.isEmpty else { return }
            open = true
            onOpenChange?(true)
            AppNativeMenu.popUp(list, under: self)
            open = false
            onOpenChange?(false)
        }

        /// The SwiftUI button underneath is the accessibility element (its press opens the same menu).
        override func isAccessibilityElement() -> Bool { false }
    }
}
