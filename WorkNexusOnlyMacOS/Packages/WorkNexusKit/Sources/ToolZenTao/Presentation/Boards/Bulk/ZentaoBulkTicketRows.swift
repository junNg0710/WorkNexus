/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SwiftUI

/// One row per picked ticket: which it is, why it would be skipped, its hours left (a task) and its own note.
struct ZentaoBulkTicketRows: View {
    @Environment(\.appTheme) private var theme
    let tickets: [Ticket]
    /// nil until a person is picked (nothing is skipped yet).
    let plan: ZenTaoBulkPlan?
    let form: ZentaoBulkAssignForm

    var body: some View {
        let skipped = Dictionary((plan?.skipped ?? []).map { ($0.ticket.id, $0.reason) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 0) {
            ZentaoFieldLabel(appFormat("leaderBulkTickets", "Tickets · %1$@", "\(tickets.count)"))
            VStack(spacing: theme.spacing.s6) {
                ForEach(tickets) { t in ZentaoBulkTicketRow(ticket: t, skip: skipped[t.id], form: form) }
            }
        }
    }
}

private struct ZentaoBulkTicketRow: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket; let skip: ZenTaoBulkSkipReason?
    @Bindable var form: ZentaoBulkAssignForm

    /// Hours the task has now, as a placeholder ("8 h left"), or what it will get from the shared field.
    private var hoursPrompt: String {
        if case .zentaoTask(let t)? = ticket.providerEntity, let left = t.left, left > 0 {
            return appFormat("taskHoursLeft", "%1$@ h left", zentaoHoursText(left))
        }
        if let shared = form.sharedHours { return appFormat("taskHoursLeft", "%1$@ h left", zentaoHoursText(shared)) }
        return appString("zentaoHoursLeft", "Hours left")
    }

    var body: some View {
        let c = theme.colors
        // Skipped for its state, its holder or its team: nothing to type. One waiting for hours still takes them.
        let editable = skip == nil || skip == .needsHours
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            HStack(spacing: theme.spacing.s6) {
                Text(verbatim: "#\(ticket.externalKey)").font(theme.typography.mono).foregroundStyle(c.tx3)
                Text(ticket.title).font(theme.typography.bodyStrong).foregroundStyle(editable ? c.tx : c.tx3).lineLimit(1)
                Spacer(minLength: theme.spacing.s4)
                if let skip { TintedPill(ZentaoBulkSummary.reason(skip), tint: skip == .needsHours ? c.red : c.amber) }
            }
            if editable {
                HStack(spacing: theme.spacing.s8) {
                    if zentaoIsTask(ticket) {
                        let typed = form.hours[ticket.id] ?? ""
                        ZentaoBulkField(text: form.hoursText(ticket.id), prompt: hoursPrompt, digits: true,
                                        warn: ZentaoBulkAssignForm.problem(typed) != nil || skip == .needsHours)
                            .frame(width: theme.sizes.boardColumnFolded * 2.6)
                            .help(appString("tipBulkHoursOne", "Hours left for this task; empty keeps what it has"))
                    }
                    ZentaoBulkField(text: form.note(ticket.id),
                                    prompt: form.sharedNote ?? appString("leaderBulkNoteOne", "Note for this ticket"))
                }
            }
        }
        .padding(theme.spacing.s10)
        .background(c.panel2.opacity(editable ? 1 : 0.5), in: RoundedRectangle(cornerRadius: theme.radii.md))
    }
}
