/// Ported from: lib/features/workspace_overview/presentation/widgets/my_work_row.dart
import CoreDomain
import CoreUI
import SwiftUI

/// One assigned bug or task: its kind, title and when it last changed, over a meta line with everything needed to
/// triage it without opening it - the reference, status, severity, priority, sprint, deadline and task tree. Opens in
/// the detail panel, and stays highlighted while open there.
struct MyWorkRow: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let ticket: Ticket
    /// Off inside a status section, whose header already says it.
    var showStatus = true

    var body: some View {
        let c = theme.colors, t = theme.typography
        let type = ticket.externalType?.lowercased()
        let updated = ticket.updatedAt ?? ticket.createdAt
        HoverSurface(onTap: { model.openTicket(ticket.id) }, selected: model.nav.openTicketId(at: .workspace) == ticket.id) {
            HStack(alignment: .top, spacing: theme.spacing.s10) {
                ZenTaoKindIcon(type)
                VStack(alignment: .leading, spacing: theme.spacing.s6) {
                    HStack(alignment: .top, spacing: theme.spacing.s8) {
                        Text(ticket.title).font(t.bodyStrong).foregroundStyle(c.tx).lineLimit(2)
                        Spacer(minLength: 0)
                        if let updated { Text(shortWhen(updated)).font(t.caption).foregroundStyle(c.tx3) }
                    }
                    FlowLayout(spacing: theme.spacing.s8, lineSpacing: theme.spacing.s4) {
                        Text(ticketRef(ticket.providerType, ticket.externalKey, ticket.externalType)).font(t.mono).foregroundStyle(c.tx3)
                        if showStatus {
                            TintedPill(myWorkStatusLabel(ticket.status, bug: type == "bug"), tint: c.statusColor(ticket.status))
                        }
                        if let severity = ticket.severity { SeverityTag(severity) }
                        PriorityTag(ticket.providerType, ticket.priority)
                        MyWorkFacts(ticket: ticket)
                    }
                }
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s10)
        }
    }
}

/// The provider-specific facts of a row: a bug's sprint / deadline / reopens, a task's parent and subtasks.
private struct MyWorkFacts: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket

    var body: some View {
        switch ticket.providerEntity {
        case .zentaoBug(let bug)?:
            if let where_ = bug.executionName ?? bug.productName {
                MyWorkFact(systemImage: "rectangle.split.3x1", text: where_, maxWidth: OverviewLayout.factNameMax)
            }
            if let due = parseZenTaoDate(bug.deadline) { MyWorkDueFact(due: due) }
            if let n = bug.activatedCount, n > 0 {
                MyWorkFact(systemImage: "arrow.counterclockwise", text: OL.reopened(n), color: theme.colors.amber)
            }
        case .zentaoTask(let task)?:
            if let parent = task.parentName, !parent.isEmpty {
                MyWorkFact(systemImage: "arrow.turn.up.left", text: parent, maxWidth: OverviewLayout.factNameMax)
            }
            if !task.subtasks.isEmpty { MyWorkFact(systemImage: "point.3.connected.trianglepath.dotted", text: OL.subtasks(task.subtasks.count)) }
        default: EmptyView()
        }
    }
}
