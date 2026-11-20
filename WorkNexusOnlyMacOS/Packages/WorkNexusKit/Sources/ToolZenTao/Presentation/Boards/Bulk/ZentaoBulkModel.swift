/// Not in the Flutter app.
import CoreDomain
import CoreUI
import Foundation
import Observation
import SharedKit

/// One bulk run on a board: progress while it goes, then what failed, so it can be shown and retried. An assign can be
/// undone from its toast: each ticket goes back to whoever held it.
@MainActor @Observable
final class ZentaoBulkModel {
    struct Progress: Equatable { var done: Int; var total: Int }
    struct Failures {
        var action: ZenTaoBulkAction
        var tickets: [Ticket]
        var messages: [String: String]
    }

    private(set) var progress: Progress?
    var failures: Failures?
    @ObservationIgnored private var stopped = false

    func stop() { stopped = true }

    /// Applies `action` to the tickets of `plan` (worked out by the dialog, which knows who can take what).
    func run(_ action: ZenTaoBulkAction, plan: ZenTaoBulkPlan, state: ZentaoUIState, bugs: Bool, toasts: AppToastController?) async {
        guard progress == nil, !plan.isEmpty else { return }
        let board = bugs ? state.bugBoard : state.taskBoard
        if case .assign(let login, _, _, _) = action, let accountId = plan.tickets.first?.accountId { state.rememberAssignee(login, accountId: accountId) }
        let result = await drive([(action, plan)], state: state, board: board)
        // What the action covered leaves the pick; what failed or never ran stays, to be retried; other picks stay.
        let covered = Set(plan.tickets.map(\.id) + plan.skipped.map(\.ticket.id))
        board.select(board.selectedIds.subtracting(covered).union(result.failed.map(\.ticketId) + result.notRun))
        var line = appFormat("leaderBulkDone", "%1$@: %2$@ done, %3$@ failed", Self.name(action), "\(result.succeeded.count)", "\(result.failed.count)")
        if !result.notRun.isEmpty { line += " " + appFormat("leaderBulkNotRun", "· %1$@ not run", "\(result.notRun.count)") }
        if !plan.skipped.isEmpty { line += " " + appFormat("leaderBulkSkippedCount", "· %1$@ skipped", "\(plan.skipped.count)") }
        // Handing work out by mistake is easy to undo: the toast carries the way back.
        var undo: (label: String, run: @MainActor () -> Void)?
        if case .assign = action, !result.succeeded.isEmpty {
            let before = plan.tickets, succeeded = result.succeeded
            // The hours each task was given go back with it: ZenTao wants them again.
            let hours = Dictionary(before.compactMap { t in action.assignment(for: t)?.left.map { (t.id, $0) } }, uniquingKeysWith: { a, _ in a })
            undo = (appString("leaderBulkUndo", "Undo"), { [weak self] in
                Task { await self?.undo(before: before, succeeded: succeeded, hours: hours, state: state, bugs: bugs, toasts: toasts) }
            })
        }
        toasts?.show(line, kind: result.isClean ? .success : .error, action: undo)
        if !result.failed.isEmpty {
            let failed = Set(result.failed.map(\.ticketId))
            failures = Failures(action: action, tickets: plan.tickets.filter { failed.contains($0.id) },
                                messages: Dictionary(result.failed.map { ($0.ticketId, $0.message) }, uniquingKeysWith: { a, _ in a }))
        }
    }

    /// What a one-click assign did: ran (or had nothing to do), or found tasks that need hours left typed in first.
    enum QuickOutcome: Equatable { case done, needsHours }

    /// Hands `tickets` to `login` in one go (the quick Assign menu, cards dropped on a person): the people of their teams
    /// are read first so a ticket the person cannot take is skipped, not refused by ZenTao. A task with no hours left
    /// cannot go in one click (ZenTao wants them): nothing runs, and the caller opens the dialog that asks.
    @discardableResult
    func quickAssign(_ login: String, tickets: [Ticket], state: ZentaoUIState, bugs: Bool, toasts: AppToastController?) async -> QuickOutcome {
        guard progress == nil, !tickets.isEmpty else { return .done }
        let teams = (try? await state.bulkAssignSource(tickets).get()).map { ZenTaoAssignTeams(members: $0.teams.mapValues { Set($0.map(\.account)) }) }
        let action = ZenTaoBulkAction.assign(login: login, comment: nil)
        let plan = PlanBulkAction()(tickets, action, canTake: teams.map { t in { t.canTake($0, $1) } })
        if !plan.skipped(.needsHours).isEmpty { return .needsHours }
        guard !plan.isEmpty else {
            let name = state.memberNames[login] ?? login
            toasts?.show(appFormat("leaderQuickAssignNothing", "Nothing to give %1$@: those tickets are theirs already, closed, or not on their team", name),
                         kind: .warning)
            return .done
        }
        await run(action, plan: plan, state: state, bugs: bugs, toasts: toasts)
        return .done
    }

    /// Gives the `succeeded` tickets of an assign back to their holders in `before` (the tickets as they were). `left` /
    /// `hours` (by ticket id): the hours the assign gave the tasks (ZenTao wants them again on the way back).
    func undo(before: [Ticket], succeeded: [String], left: Double? = nil, hours: [String: Double] = [:], state: ZentaoUIState, bugs: Bool,
              toasts: AppToastController?) async {
        guard progress == nil else { return }
        let plan = PlanBulkUndo()(before: before, succeeded: succeeded)
        let none = plan.cannotUndo.isEmpty ? "" : " " + appFormat("leaderBulkUndoNobody", "· %1$@ had nobody before", "\(plan.cannotUndo.count)")
        guard !plan.isEmpty else {
            toasts?.show(appString("leaderBulkUndoNothing", "Nothing to undo: those tickets had nobody before") , kind: .warning)
            return
        }
        // Each former holder's tickets as they are: they are not "unchanged", whatever the store still says.
        let batches = plan.steps.map { step in
            let details = Dictionary(step.tickets.compactMap { t in hours[t.id].map { (t.id, ZenTaoAssignDetail(left: $0)) } }, uniquingKeysWith: { a, _ in a })
            return (ZenTaoBulkAction.assign(login: step.login, comment: nil, left: left, details: details), ZenTaoBulkPlan(tickets: step.tickets, skipped: []))
        }
        let result = await drive(batches, state: state, board: bugs ? state.bugBoard : state.taskBoard)
        let line = appFormat("leaderBulkUndone", "Undo: %1$@ back, %2$@ failed", "\(result.succeeded.count)", "\(result.failed.count)") + none
        toasts?.show(line, kind: result.failed.isEmpty && result.notRun.isEmpty ? .success : .error)
    }

    /// Runs each batch one after another, one progress over all of them; a stop leaves the rest not run.
    private func drive(_ batches: [(ZenTaoBulkAction, ZenTaoBulkPlan)], state: ZentaoUIState, board: BoardController) async -> ZenTaoBulkResult {
        stopped = false
        let ids = batches.flatMap { $0.1.tickets.map(\.id) }
        ids.forEach(board.beginAction)
        progress = Progress(done: 0, total: ids.count)
        let me = self, ops = state.bulkOps()
        var total = ZenTaoBulkResult()
        var offset = 0
        for (action, plan) in batches {
            let base = offset
            let result = await RunZenTaoBulkAction(ops: ops)(
                plan, action,
                shouldContinue: { await MainActor.run { !me.stopped } },
                progress: { done, _ in
                    await MainActor.run { me.progress = Progress(done: base + done, total: ids.count); board.endAction(ids[base + done - 1]) }
                })
            total.succeeded += result.succeeded; total.failed += result.failed; total.notRun += result.notRun
            offset += plan.tickets.count
        }
        ids.forEach(board.endAction)
        progress = nil
        return total
    }

    static func name(_ action: ZenTaoBulkAction) -> String {
        switch action {
        case .assign: appString("assign", "Assign")
        case .priority: appString("priority", "Priority")
        case .close: appString("leaderBulkCloseName", "Close")
        }
    }
}
