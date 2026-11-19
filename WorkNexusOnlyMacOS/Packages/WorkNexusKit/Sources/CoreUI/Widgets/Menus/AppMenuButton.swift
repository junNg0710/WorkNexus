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
    @State private var anchor = MenuAnchor()

    public init(help: String? = nil, items: @escaping () -> [AppNativeMenu.Item], @ViewBuilder label: () -> Label) {
        self.items = items; self.help = help; self.label = label()
    }

    public var body: some View {
        Button {
            let list = items()
            if let view = anchor.view { AppNativeMenu.popUp(list, under: view) } else { AppNativeMenu.popUp(list) }
        } label: { label.contentShape(Rectangle()) }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: anchor))
        .help(help ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// Where the menu is shown from: the AppKit view behind the button.
@MainActor final class MenuAnchor {
    weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor
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
