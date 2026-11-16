/// Ported from: lib/shared/detail/presentation/widgets/assign_dialog.dart, detail/zentao_task_assign_dialog.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Hands a ticket to someone through its adapter, then re-reads it from ZenTao (the DB stream shows the change).
@MainActor
enum ZentaoAssignAction {
    static func run(deps: ZentaoDependencies, ticket: Ticket, assignee: String, comment: String?, left: Double?) async -> Outcome<Void> {
        guard let account = await deps.account(id: ticket.accountId), let adapter = await deps.services.sync.adapter(for: account) else {
            return .failure(.auth("No stored credentials for this account"))
        }
        if case .failure(let f) = await adapter.assignTicket(ticket, assignee: assignee, comment: comment, left: left) { return .failure(f) }
        return await deps.services.ticketDetail.refresh(ticket: ticket)
    }
}

/// Assigns a bug (or story) to a user, with an optional note.
struct ZentaoAssignDialog: View {
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let state: ZentaoUIState; let ticket: Ticket; let onClose: () -> Void
    @State private var note: ZentaoNoteModel
    @State private var assignee: String?
    @State private var busy = false

    init(deps: ZentaoDependencies, state: ZentaoUIState, ticket: Ticket, onClose: @escaping () -> Void) {
        self.deps = deps; self.state = state; self.ticket = ticket; self.onClose = onClose
        _note = State(initialValue: ZentaoNoteModel(ticket: ticket))
    }

    private func submit() {
        guard let assignee else { return }
        busy = true
        let t = ticket, deps = deps, comment = note.value
        Task {
            await ZentaoActionRunner.run(state: state, ticket: t, toasts: toasts, label: appString("assign", "Assign"),
                                         successMessage: appFormat("taskDetailAssignedTo", "Assigned to %1$@", assignee)) {
                await ZentaoAssignAction.run(deps: deps, ticket: t, assignee: assignee, comment: comment, left: nil)
            }
            onClose()
        }
    }

    var body: some View {
        let title = appString("assign", "Assign")
        ZentaoActionFrame(title: ZentaoActionLooks.title(title, ticket.externalKey), icon: "person.badge.plus", submitLabel: title,
                          busy: busy, canSubmit: assignee != nil, onSubmit: submit, onClose: onClose) {
            ZentaoFieldLabel(appString("fieldAssignTo", "Assign to"))
            ZentaoAssigneeDropdown(deps: deps, ticket: ticket, value: assignee) { assignee = $0 }
            ZentaoFieldGap()
            ZentaoFieldLabel(appString("zentaoNote", "Note"))
            ZentaoNoteField(deps: deps, ticket: ticket, note: note)
        }
    }
}

/// Assigns a ZenTao task as ZenTao's own form does: who it goes to, the hours left (required until the task is done)
/// and a note.
struct ZentaoTaskAssignDialog: View {
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let state: ZentaoUIState; let ticket: Ticket; let onClose: () -> Void
    @State private var note: ZentaoNoteModel
    // Prefilled with what the task has left, as ZenTao's form is.
    @State private var left: String
    @State private var assignee: String?
    @State private var busy = false

    init(deps: ZentaoDependencies, state: ZentaoUIState, ticket: Ticket, onClose: @escaping () -> Void) {
        self.deps = deps; self.state = state; self.ticket = ticket; self.onClose = onClose
        _note = State(initialValue: ZentaoNoteModel(ticket: ticket))
        if case .zentaoTask(let t) = ticket.providerEntity, let l = t.left, l > 0 { _left = State(initialValue: zentaoHoursText(l)) }
        else { _left = State(initialValue: "") }
    }

    /// ZenTao hides the hours left on a done task: it has none to hand over.
    private var asksLeft: Bool { ticket.providerStatus.trimmingCharacters(in: .whitespaces).lowercased() != "done" }

    private func submit() {
        guard let assignee else { return }
        busy = true
        let t = ticket, deps = deps, comment = note.value, hours: Double? = asksLeft ? zentaoParseHours(left) : nil
        Task {
            await ZentaoActionRunner.run(state: state, ticket: t, toasts: toasts, label: appString("assign", "Assign"),
                                         successMessage: appFormat("taskDetailAssignedTo", "Assigned to %1$@", assignee)) {
                await ZentaoAssignAction.run(deps: deps, ticket: t, assignee: assignee, comment: comment, left: hours)
            }
            onClose()
        }
    }

    var body: some View {
        let title = appString("assign", "Assign")
        let problem = asksLeft ? CheckZenTaoAssignLeft()(zentaoParseHours(left)) : nil
        ZentaoActionFrame(title: ZentaoActionLooks.title(title, ticket.externalKey), icon: "person.badge.plus", submitLabel: title,
                          busy: busy, canSubmit: assignee != nil && problem == nil, onSubmit: submit, onClose: onClose) {
            ZentaoFieldLabel(appString("fieldAssignTo", "Assign to"))
            ZentaoAssigneeDropdown(deps: deps, ticket: ticket, value: assignee) { assignee = $0 }
            ZentaoFieldGap()
            if asksLeft {
                ZentaoTaskHoursField(label: appString("zentaoHoursLeft", "Hours left"), text: $left)
                if let problem { ZentaoTaskProblemLine(problem) }
                ZentaoFieldGap()
            }
            ZentaoFieldLabel(appString("zentaoNote", "Note"))
            ZentaoNoteField(deps: deps, ticket: ticket, note: note)
        }
    }
}
