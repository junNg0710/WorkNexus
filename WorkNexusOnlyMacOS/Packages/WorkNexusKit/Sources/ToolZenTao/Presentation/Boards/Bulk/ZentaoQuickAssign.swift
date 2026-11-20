/// Not in the Flutter app: handing tickets out in one click - from the bulk bar's menu, or by dropping cards on a person.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Cards dropped on a person of the people strip; the bulk bar of the matching board assigns them.
struct ZentaoBulkDrop: Hashable { var bugs: Bool; var login: String; var ids: Set<String> }

/// The bulk bar's Assign: a menu of the pinned and recent people (one click hands every picked ticket over), then
/// "Someone else…" for the full dialog. With nobody to offer yet, it opens the dialog straight away.
struct ZentaoQuickAssignButton: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let enabled: Bool
    let onPick: (String) -> Void; let onOther: () -> Void

    var body: some View {
        let quick = state.quickAssignees
        let label = appString("leaderBulkAssign", "Assign…")
        if quick.isEmpty {
            AppButton(label, systemImage: "person.badge.plus", kind: .ghost, action: onOther).disabled(!enabled)
                .help(appString("tipBulkAssign", "Give every selected ticket to one person"))
        } else {
            AppMenuButton(help: appString("tipQuickAssign", "Give every selected ticket to a pinned or recent person, or pick someone else"),
                          items: { items(quick) }) {
                HStack(spacing: theme.spacing.s6) {
                    Image(systemName: "person.badge.plus").font(.system(size: theme.sizes.icon14))
                    Text(label).font(theme.typography.label)
                    Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12 - 2))
                }
                .foregroundStyle(theme.colors.tx)
                .padding(.horizontal, theme.spacing.s12).frame(height: theme.sizes.control32)
                .contentShape(Rectangle())
            }
            .fixedSize()
            .disabled(!enabled)
        }
    }

    private func items(_ quick: [String]) -> [AppNativeMenu.Item] {
        let pinned = Set(state.pinnedPeople), names = state.memberNames
        var out = quick.map { login in
            AppNativeMenu.Item(names[login] ?? login, icon: pinned.contains(login) ? "pin" : "clock.arrow.circlepath") { onPick(login) }
        }
        out.append(.init(appString("leaderQuickAssignOther", "Someone else…"), icon: "person.crop.circle.badge.plus", dividerBefore: true, action: onOther))
        return out
    }
}

/// What a card carries when dragged: its id, and that a card (not a person chip) is on the move. Dragged while picked
/// with others, its preview says how many go with it.
struct ZentaoTicketDrag: ViewModifier {
    let state: ZentaoUIState; let controller: BoardController; let ticket: Ticket
    /// Told as the card lifts (the bug board dims the one left behind).
    var onLift: (() -> Void)?

    func body(content: Content) -> some View {
        content.onDrag({
            let lift = onLift
            DispatchQueue.main.async { state.draggingTickets = true; lift?() }
            return NSItemProvider(object: ticket.id as NSString)
        }, preview: { ZentaoCardDragPreview(controller: controller, ticket: ticket) })
    }
}

private struct ZentaoCardDragPreview: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController; let ticket: Ticket

    var body: some View {
        let picked = controller.selectedIds
        let count = picked.contains(ticket.id) ? picked.count : 1
        TicketCardDragPreview { ZentaoBoardCard(controller: controller, ticket: ticket) }
            .overlay(alignment: .topLeading) {
                if count > 1 {
                    Text(appFormat("leaderDragCount", "%1$@ tickets", "\(count)")).font(theme.typography.metaStrong)
                        .foregroundStyle(theme.colors.accentTx)
                        .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s2)
                        .background(theme.colors.accent, in: Capsule())
                        .offset(x: -theme.spacing.s6, y: -theme.spacing.s8)
                }
            }
    }
}
