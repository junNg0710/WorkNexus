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
    /// The cards drawn with this one (its column), in order: where a ⇧-click picks a range.
    var among: [String] = []

    var body: some View {
        let c = theme.colors
        let wsColor = controller.workspaceColorValue(of: ticket).map { Color(argb: UInt32(truncatingIfNeeded: $0)) } ?? c.workspaceFallback
        let picked = controller.selectedIds.contains(ticket.id)
        let selected = controller.openTicketId == ticket.id || picked
        let pending = controller.pendingTicketIds.contains(ticket.id)
        let title = ZentaoFormatters.extractTags(ticket.title).title
        let bg = selected ? c.mix(c.card, wsColor, 0.16) : c.tintedCard(wsColor, enabled: controller.settings.companyTint)
        HoverSurface(onTap: pending ? nil : { controller.tapTicket(ticket.id, among: among) }, enabled: !pending, fill: bg,
                     border: selected ? c.accent : (theme.showOutline ? c.line : nil), cornerRadius: theme.radii.card) {
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                ZentaoCardTopLine(ticket: ticket)
                if case .zentaoTask(let t)? = ticket.providerEntity, t.parentId != nil { ZentaoCardParentLine(ticket: ticket) }
                ZentaoCardScopeLine(ticket: ticket)
                Text(title).font(theme.typography.bodyStrong).foregroundStyle(c.tx).lineLimit(3)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                ZentaoDeadlineTag(ticket: ticket)
                HStack(spacing: theme.spacing.s6) {
                    AssigneeChip(ticket.assignee, accent: wsColor, accountId: ticket.accountId).frame(maxWidth: .infinity, alignment: .leading)
                    ZentaoCardHoursLeft(ticket: ticket)
                    accessory?(ticket)
                }
            }
            .padding(theme.cardPadding)
        }
        .overlay(alignment: .topTrailing) {
            if picked {
                // A badge on the card's corner, clear of the age text beside it.
                Image(systemName: "checkmark.circle.fill").font(.system(size: theme.sizes.icon14)).foregroundStyle(c.accent)
                    .background(Circle().fill(c.card)).offset(x: theme.spacing.s4, y: -theme.spacing.s4)
            }
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

/// How late an overdue ticket is, in the error colour.
struct ZentaoDelayTag: View {
    @Environment(\.appTheme) private var theme
    let text: String
    var tint: Color?
    var body: some View {
        let color = tint ?? theme.colors.red
        Text(text).font(theme.typography.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: theme.radii.xs))
    }
}

/// What a card says about its deadline: how many days late (red), or that it is due today or within a few days
/// (amber). Nothing for a ticket that is finished, has no deadline or is not due soon.
struct ZentaoDeadlineTag: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        switch zentaoDeadlineState(ticket) {
        case .overdue(let days):
            ZentaoDelayTag(text: days == 1 ? appString("zentaoDelayOneDay", "Delay 1 day") : appFormat("zentaoDelayDays", "Delay %1$@ days", "\(days)"))
        case .today:
            ZentaoDelayTag(text: appString("zentaoDueToday", "Due today"), tint: theme.colors.amber)
        case .upcoming(let days) where days <= ZenTaoLeaderFilter.soonDays:
            ZentaoDelayTag(text: days == 1 ? appString("zentaoDueTomorrow", "Due tomorrow") : appFormat("leaderDueSoon", "Due in %1$@ days", "\(days)"), tint: theme.colors.amber)
        default:
            EmptyView()
        }
    }
}

/// "2 h left" on a task card that has hours to do.
struct ZentaoCardHoursLeft: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        if case .zentaoTask(let t)? = ticket.providerEntity, let left = t.left, left > 0, zentaoIsOpen(ticket) {
            Text(appFormat("taskHoursLeft", "%1$@ h left", zentaoHoursText(left))).font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
        }
    }
}

