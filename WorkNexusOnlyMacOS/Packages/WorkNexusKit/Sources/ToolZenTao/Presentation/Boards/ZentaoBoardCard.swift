/// Ported from: lib/tools/zentao/presentation/widgets/zentao_board_card.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// A ZenTao bug's or task's card on its board, kept to what triage needs: the id, severity (bugs), priority and how
/// long ago it changed; a subtask's parent; the title without the bracketed tags ZenTao titles start with
/// ("[Discovery]"); how late an overdue task is; the assignee. Tapping opens the detail slide-over.
struct ZentaoBoardCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.ticketCardAccessory) private var accessory
    let controller: BoardController; let ticket: Ticket

    var body: some View {
        let c = theme.colors
        let wsColor = controller.workspaceColorValue(of: ticket).map { Color(argb: UInt32(truncatingIfNeeded: $0)) } ?? c.workspaceFallback
        let selected = controller.openTicketId == ticket.id
        let pending = controller.pendingTicketIds.contains(ticket.id)
        let title = ZentaoFormatters.extractTags(ticket.title).title
        let bg = selected ? c.mix(c.card, wsColor, 0.16) : c.tintedCard(wsColor, enabled: controller.settings.companyTint)
        HoverSurface(onTap: pending ? nil : { controller.openTicket(ticket.id) }, enabled: !pending, fill: bg,
                     border: selected ? c.accent : (theme.showOutline ? c.line : nil), cornerRadius: theme.radii.card) {
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                ZentaoCardTopLine(ticket: ticket)
                if case .zentaoTask(let t)? = ticket.providerEntity, t.parentId != nil { ZentaoCardParentLine(ticket: ticket) }
                Text(title).font(theme.typography.bodyStrong).foregroundStyle(c.tx).lineLimit(3)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                if let late = ZentaoFormatters.delayText(ZentaoFormatters.extractDeadline(ticket)) { ZentaoDelayTag(text: late) }
                HStack(spacing: theme.spacing.s6) {
                    AssigneeChip(ticket.assignee, accent: wsColor, accountId: ticket.accountId).frame(maxWidth: .infinity, alignment: .leading)
                    accessory?(ticket)
                }
            }
            .padding(theme.cardPadding)
        }
        .opacity(pending ? 0.48 : 1)
        .zentaoRowContextMenu(ticket: ticket)
    }
}

/// "#7265", severity, priority, and how long ago the ticket changed.
struct ZentaoCardTopLine: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        HStack(spacing: theme.spacing.s6) {
            Text("#\(ticket.externalKey)").font(theme.typography.mono).foregroundStyle(theme.colors.tx3)
            if let s = ticket.severity { SeverityTag(s) }
            if hasExplicitPriority(ticket) { PriorityTag(ticket.providerType, ticket.priority) }
            Spacer(minLength: 0)
            if let age = Self.age(ticket.updatedAt) { Text(age).font(theme.typography.caption).foregroundStyle(theme.colors.tx3) }
        }
    }

    /// "5m ago", "3h ago", "2d ago"; nothing without a time.
    static func age(_ at: Date?, now: Date = Date()) -> String? {
        guard let at else { return nil }
        let seconds = max(now.timeIntervalSince(at), 0)
        let hours = Int(seconds / 3600), minutes = max(Int(seconds / 60), 1)
        if hours < 1 { return appFormat("minutesAgo", "%1$@m ago", "\(minutes)") }
        if hours < 24 { return appFormat("hoursAgo", "%1$@h ago", "\(hours)") }
        return appFormat("daysAgo", "%1$@d ago", "\(hours / 24)")
    }
}

/// How late an overdue task is, in the error colour.
struct ZentaoDelayTag: View {
    @Environment(\.appTheme) private var theme
    let text: String
    var body: some View {
        Text(text).font(theme.typography.caption.weight(.semibold)).foregroundStyle(theme.colors.red)
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
            .background(theme.colors.red.opacity(0.12), in: RoundedRectangle(cornerRadius: theme.radii.xs))
    }
}

