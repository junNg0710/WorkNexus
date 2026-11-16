import AppKit
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{detail_panel_header_actions,detail_back_button,detail_header_copy_link_button}.dart
/// Panel-level (non-state-changing) actions of a two-pane detail header: refresh, copy link, open in browser, edit on
/// the web page, and close the panel.
struct GitlabPanelHeaderActions<MenuContent: View>: View {
    @Environment(\.toasts) private var toasts
    let url: String?; let onSync: () -> Void; let onClosePanel: () -> Void
    /// An item-specific "more" menu (the MR's state actions), placed just before the close-panel button.
    let menu: MenuContent

    init(url: String?, onSync: @escaping () -> Void, onClosePanel: @escaping () -> Void, @ViewBuilder menu: () -> MenuContent) {
        self.url = url; self.onSync = onSync; self.onClosePanel = onClosePanel; self.menu = menu()
    }

    var body: some View {
        HStack(spacing: 4) {
            AppIconButton("arrow.clockwise", help: appString("refresh", "Refresh"), action: onSync)
            if let url, !url.isEmpty {
                AppIconButton("link", help: appString("copyLink", "Copy link")) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string)
                    toasts?.show(appString("linkCopied", "Copied!"))
                }
                AppIconButton("arrow.up.right.square", help: appString("openInBrowser", "Open in browser")) { openLinkExternally(url, inApp: false) }
                AppIconButton("pencil", help: appString("edit", "Edit")) { openLinkExternally("\(url)/edit", inApp: false) }
            }
            menu
            AppIconButton("xmark", help: appString("close", "Close"), action: onClosePanel)
        }
    }
}

/// Leads a detail header with "back to the previous ticket", shown only once a ticket was opened from inside the panel.
struct GitlabBackButton: View {
    let nav: AppNavController
    var body: some View {
        if (nav.state.ticketHistories[nav.state.rail.key]?.count ?? 0) > 1 {
            AppIconButton("arrow.left", help: appString("back", "Back")) { nav.goBackTicket() }
        }
    }
}
