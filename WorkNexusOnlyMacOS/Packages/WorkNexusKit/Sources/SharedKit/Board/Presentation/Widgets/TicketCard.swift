import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/ticket_card.dart
/// A board card: workspace-coloured stripe, ref + severity/priority tags, title, labels, assignee. Tapping opens the
/// detail slide-over; the workspace colour tint follows the "company tint" setting.
public struct TicketCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.ticketCardAccessory) private var accessory
    let controller: BoardController
    let ticket: Ticket

    public init(_ ticket: Ticket, controller: BoardController) { self.ticket = ticket; self.controller = controller }

    public var body: some View {
        let c = theme.colors
        let wsColor = controller.workspaceColorValue(of: ticket).map { Color(argb: UInt32(truncatingIfNeeded: $0)) } ?? c.workspaceFallback
        let selected = controller.openTicketId == ticket.id
        let pending = controller.pendingTicketIds.contains(ticket.id)
        let labels = visibleUserLabels(ticket.labels)
        let colors = labelColorsOf(ticket)
        let stripe: CGFloat = selected ? 5 : 4
        let bg = selected ? c.mix(c.card, wsColor, 0.16) : c.tintedCard(wsColor, enabled: controller.settings.companyTint)
        HoverSurface(onTap: pending ? nil : { controller.openTicket(ticket.id) }, enabled: !pending, fill: bg,
                     border: theme.showOutline ? c.line : nil, cornerRadius: theme.radii.card) {
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                HStack(spacing: theme.spacing.s6) {
                    Text(ticketRef(ticket.providerType, ticket.externalKey, ticket.externalType))
                        .font(theme.typography.mono).foregroundStyle(c.tx2)
                        .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
                        .background(c.panel2, in: RoundedRectangle(cornerRadius: theme.radii.xs))
                    if case .gitlabItem(let g)? = ticket.providerEntity, let path = g.projectPath, !path.isEmpty {
                        TicketCardProjectPath(path: path)
                    }
                    Spacer(minLength: 0)
                    if let s = ticket.severity { SeverityTag(s) }
                    if hasExplicitPriority(ticket) { PriorityTag(ticket.providerType, ticket.priority) }
                }
                Text(ticket.title).font(theme.typography.bodyStrong).foregroundStyle(c.tx).lineLimit(3)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                if !labels.isEmpty { LabelChips(labels, colors: colors.background, textColors: colors.text) }
                HStack(spacing: theme.spacing.s6) {
                    AssigneeChip(ticket.assignee, accent: wsColor, accountId: ticket.providerType == .zentao ? ticket.accountId : nil)
                    Spacer(minLength: 0)
                    accessory?(ticket)
                }
            }
            .padding(theme.cardPadding).padding(.leading, stripe)
            .background(alignment: .leading) {
                Rectangle().fill(wsColor).frame(width: stripe)
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.card))
        }
        .opacity(pending ? 0.48 : 1)
    }
}

private struct TicketCardProjectPath: View {
    @Environment(\.appTheme) private var theme
    let path: String
    var body: some View {
        let label = path.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "/")
        HStack(spacing: theme.spacing.s4) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: theme.sizes.icon12))
            Text(label).font(theme.typography.caption).lineLimit(1)
        }
        .foregroundStyle(theme.colors.tx3).help(label)
    }
}
