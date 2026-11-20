/// Not in the Flutter app.
import AppKit
import SwiftUI

/// A button that opens a native menu under itself: the app's dropdowns and "…" buttons.
///
/// A SwiftUI `Menu` lives inside the view tree, so whatever redraws the views around it while it is open — a hover
/// handler, a panel sliding, a chat message or presence update arriving — could close it, or swallow the pick, which made
/// dropdowns all over the app "not take a click". AppKit runs this menu itself until a pick or Esc, whatever the views do
/// meanwhile. `items` is read when the button is pressed, so the menu always shows the current state.
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
        .appMenuAnchor(anchor)
        .help(help ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// Where a button's menu is shown from: the AppKit view behind it (`appMenuAnchor`). A menu opened under the pointer
/// instead covered the button that opened it and put its first item right under the click, so a "…" button seemed hard
/// to press - a click that landed a hair later picked that item or closed the menu.
@MainActor public final class AppMenuAnchor {
    weak var view: NSView?
    public init() {}
}

public extension View {
    /// Marks this view as where `anchor`'s menu opens: just under it (`AppNativeMenu.popUp(_:under:)`).
    func appMenuAnchor(_ anchor: AppMenuAnchor) -> some View { background(MenuAnchorView(anchor: anchor)) }
}

public extension AppNativeMenu {
    /// Shows the menu just under the view `anchor` marks; under the pointer only when that view is not there.
    @MainActor static func popUp(_ items: [Item], under anchor: AppMenuAnchor) {
        if let view = anchor.view { popUp(items, under: view) } else { popUp(items) }
    }
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: AppMenuAnchor
    func makeNSView(context: Context) -> NSView {
        let v = FlippedView()
        anchor.view = v
        return v
    }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }

    /// Top-left origin, so "just below" is the view's height.
    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
