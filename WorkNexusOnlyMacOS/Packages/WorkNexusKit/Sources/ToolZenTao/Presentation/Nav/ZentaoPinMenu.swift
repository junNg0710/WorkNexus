import CoreUI
import SwiftUI

/// Right-click on a product or execution in a picker ("Other products…", the project list): pin it to the side panel,
/// or unpin it. A pinned row also shows a pin. Not in the Flutter app (there only the side panel's rows pin).
struct ZentaoPinMenu: ViewModifier {
    let pinned: Bool
    let toggle: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: toggle) {
                Label(pinned ? appString("zentaoUnpinFromPanel", "Unpin from the side panel")
                             : appString("zentaoPinToPanel", "Pin to the side panel"),
                      systemImage: pinned ? "pin.slash" : "pin")
            }
        }
    }
}

/// The pin a pinned row of a picker shows.
struct ZentaoPinMark: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        Image(systemName: "pin.fill").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.accent)
            .accessibilityLabel(appString("pinned", "Pinned"))
    }
}

extension View {
    func zentaoPinMenu(pinned: Bool, toggle: @escaping () -> Void) -> some View { modifier(ZentaoPinMenu(pinned: pinned, toggle: toggle)) }
}
