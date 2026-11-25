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
/// The mouse opens it from an AppKit view over the label (`appMenu`): a click opens it once the button is released, a
/// held press at once, as a pull-down (`MenuPress`). The SwiftUI button underneath is what the keyboard and
/// accessibility press.
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
    /// The menu is run from AppKit's own mouse handling: opened from a SwiftUI button's action, a menu in the window's
    /// title area closed again the moment it appeared. A click opens it and it stays until something is picked; a press
    /// held, a drag to an item and a release picks it, as in any pull-down (`MenuPress`). `onOpenChange` says when it
    /// opens and when it has closed.
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
            // A click's release is taken here, before the menu opens: see `MenuPress`.
            _ = MenuPress.isClick(event, in: window)
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


/// Tells a click on a menu button from a held press.
///
/// A menu opened while the mouse button is down relies on AppKit to keep it open when the button comes up ("was that a
/// click, or the end of a drag to an item?"). In the ticket panel it answered "a drag" for a plain click: the menu showed
/// for the tenth of a second the button was down and closed as it came up, so nothing in it could be picked. So a click's
/// release is waited for and taken off the queue first; the menu then opens with no button down, and no release left to
/// close it. A press still held after `clickTime`, or dragged off, opens the menu at once: released on an item, it picks it.
@MainActor
enum MenuPress {
    /// How long a press may last and still be a click.
    static let clickTime: TimeInterval = 0.25
    /// How far the pointer may move during a click.
    static let slop: CGFloat = 4

    /// Waits for the release that follows `press` and says whether it was a click. Returns as soon as that is known.
    static func isClick(_ press: NSEvent, in window: NSWindow?, within clickTime: TimeInterval = MenuPress.clickTime) -> Bool {
        guard let window else { return false }
        let deadline = Date().addingTimeInterval(clickTime)
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: deadline, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { return true }
            let from = press.locationInWindow, to = next.locationInWindow
            if hypot(to.x - from.x, to.y - from.y) > slop { return false }
        }
        return false
    }
}
