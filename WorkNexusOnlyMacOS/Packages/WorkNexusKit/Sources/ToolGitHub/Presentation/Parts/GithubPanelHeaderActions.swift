import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{detail_panel_header_actions,detail_back_button,detail_header_copy_link_button}.dart
/// Panel-level (non-state-changing) actions of a two-pane detail header: refresh, copy link, open in browser, edit on
/// the web page, and close the panel.
struct GithubPanelHeaderActions: View {
    @Environment(\.appTheme) private var theme
    let url: String?; let onSync: () -> Void; let onClosePanel: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            AppIconButton("arrow.clockwise", help: appString("refresh", "Refresh"), outlined: true, action: onSync)
            if let url, !url.isEmpty {
                CopyLinkButton(url: url)
                AppIconButton("arrow.up.right.square", help: appString("openInBrowser", "Open in browser"), outlined: true) { openLinkExternally(url, inApp: false) }
                AppIconButton("pencil", help: appString("edit", "Edit"), outlined: true) { openLinkExternally("\(url)/edit", inApp: false) }
            }
            AppIconButton("xmark", help: appString("close", "Close"), outlined: true, action: onClosePanel)
        }
    }
}

/// Leads a detail header with "back to the previous ticket", shown only once a ticket was opened from inside the panel.
struct GithubBackButton: View {
    let nav: AppNavController
    var body: some View {
        if (nav.state.ticketHistories[nav.state.rail.key]?.count ?? 0) > 1 {
            AppIconButton("arrow.left", help: appString("back", "Back")) { nav.goBackTicket() }
        }
    }
}
