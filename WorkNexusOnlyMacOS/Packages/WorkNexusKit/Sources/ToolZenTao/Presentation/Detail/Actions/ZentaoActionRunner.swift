/// Ported from: the submit handlers of detail/{zentao_bug_action_dialog,resolve_dialog,zentao_task_action_dialog}.dart
import CoreDomain
import CoreUI
import Foundation

/// Runs a ticket action while its card shows as busy, then reports the outcome in a toast.
@MainActor
enum ZentaoActionRunner {
    /// The board the ticket sits on (its cards dim while an action runs).
    static func board(_ state: ZentaoUIState, _ ticket: Ticket) -> BoardMarker {
        zentaoKind(ticket) == "bug" ? BoardMarker(begin: state.bugBoard.beginAction, end: state.bugBoard.endAction)
                                    : BoardMarker(begin: state.taskBoard.beginAction, end: state.taskBoard.endAction)
    }

    struct BoardMarker { let begin: (String) -> Void; let end: (String) -> Void }

    /// - Returns: whether the action succeeded.
    @discardableResult
    static func run(state: ZentaoUIState, ticket: Ticket, toasts: AppToastController?, label: String,
                    successMessage: String? = nil, _ action: () async -> Outcome<Void>) async -> Bool {
        let marker = board(state, ticket)
        marker.begin(ticket.id)
        let result = await action()
        marker.end(ticket.id)
        let ok = result.value != nil
        let message = ok ? (successMessage ?? ZentaoActionLooks.outcome(result, action: label, key: ticket.externalKey))
                         : ZentaoActionLooks.outcome(result, action: label, key: ticket.externalKey)
        toasts?.show(message, kind: ok ? .success : .error)
        return ok
    }
}
