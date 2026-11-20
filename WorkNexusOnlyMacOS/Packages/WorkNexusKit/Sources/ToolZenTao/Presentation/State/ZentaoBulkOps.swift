/// Not in the Flutter app: what a team leader's bulk action does to one ZenTao ticket, through the interfaces the
/// detail panel's own actions use.
import CoreDomain
import Foundation

struct ZentaoBulkOps: ZenTaoBulkTicketOps {
    let workflow: ZenTaoWorkflowService
    let editor: ZenTaoTicketEditor
    /// Hands a ticket to a person and re-reads it (`ZentaoAssignAction`).
    let assigner: @Sendable (Ticket, String, String?) async -> Outcome<Void>

    func assign(_ ticket: Ticket, to login: String, comment: String?) async -> Outcome<Void> { await assigner(ticket, login, comment) }

    func close(_ ticket: Ticket) async -> Outcome<Void> {
        if case .zentaoTask? = ticket.providerEntity { return await workflow.runTaskAction(ticket, .close, ZenTaoTaskActionInput()) }
        return await workflow.closeBug(ticket, comment: nil)
    }

    /// Opens the ticket's own edit form, changes only the priority and saves it as the edit page does (which stores the
    /// ticket again), so every other field goes back as ZenTao sent it.
    func setPriority(_ ticket: Ticket, to pri: Int) async -> Outcome<Void> {
        let uid = String(Int(Date().timeIntervalSince1970 * 1_000_000), radix: 16)
        if case .zentaoTask? = ticket.providerEntity {
            switch await editor.editTaskForm(accountId: ticket.accountId, taskId: ticket.externalKey) {
            case .failure(let f): return .failure(f)
            case .success(var form):
                form.draft.pri = pri
                return await editor.saveTask(accountId: ticket.accountId, form: form, draft: form.draft, uid: uid).map { _ in () }
            }
        }
        switch await editor.editBugForm(accountId: ticket.accountId, bugId: ticket.externalKey) {
        case .failure(let f): return .failure(f)
        case .success(var form):
            form.draft.pri = pri
            return await editor.saveBug(accountId: ticket.accountId, form: form, draft: form.draft, uid: uid).map { _ in () }
        }
    }
}
