/// Not in the Flutter app: the ways into picking mode, beside ⌘-click and ⇧-click.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The toolbar's Select / Done button: turns picking mode on and off. While on, ⌘A picks every ticket the board shows.
/// Drawn like the toolbar's Sort button beside it, in the accent while on.
struct ZentaoSelectButton: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool

    var body: some View {
        let board = bugs ? state.bugBoard : state.taskBoard
        let on = board.isSelecting
        let c = theme.colors
        let ink = on ? c.accent : c.tx2
        Button { if on { board.endSelecting() } else { board.beginSelecting() } } label: {
            HStack(spacing: theme.spacing.s6) {
                Image(systemName: on ? "checkmark.circle.fill" : "checkmark.circle").font(.system(size: theme.sizes.icon14))
                Text(on ? appString("leaderSelectDone", "Done") : appString("leaderSelectMode", "Select"))
                    .font(theme.typography.metaStrong).lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, theme.spacing.s12).frame(height: theme.sizes.control32)
            .background(on ? c.sel : c.panel, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay {
                if theme.showOutline || on {
                    RoundedRectangle(cornerRadius: theme.radii.md).stroke(on ? c.accent : c.line, lineWidth: theme.borders.hairline)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: theme.radii.md))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(on ? appString("tipSelectModeDone", "Stop picking and drop the selection (Esc)")
                 : appString("tipSelectMode", "Pick several tickets to assign, reprioritise or close them together"))
        .background {
            // Present only in picking mode, so ⌘A keeps selecting text everywhere else.
            if on {
                Button("") { state.selectAllShown(bugs: bugs) }.keyboardShortcut("a", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
            }
        }
    }
}

/// A column header's checkbox in picking mode: picks or drops the column's cards.
struct ZentaoColumnSelectAll: View {
    let controller: BoardController; let tickets: [Ticket]

    var body: some View {
        if controller.isSelecting && !tickets.isEmpty { BoardSelectAllCheck(controller: controller, ids: tickets.map(\.id)) }
    }
}
