/// Not in the Flutter app.
import CoreDomain
import CoreUI
import Foundation
import Observation

/// One bulk run on a board: progress while it goes, then what failed, so it can be shown and retried.
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

    func run(_ action: ZenTaoBulkAction, on tickets: [Ticket], state: ZentaoUIState, bugs: Bool, toasts: AppToastController?) async {
        let plan = PlanBulkAction()(tickets, action)
        guard progress == nil, !plan.isEmpty else { return }
        stopped = false
        let board = bugs ? state.bugBoard : state.taskBoard
        let ids = plan.tickets.map(\.id)
        ids.forEach(board.beginAction)
        progress = Progress(done: 0, total: ids.count)
        let me = self
        let result = await RunZenTaoBulkAction(ops: state.bulkOps())(
            plan, action,
            shouldContinue: { await MainActor.run { !me.stopped } },
            progress: { done, total in
                await MainActor.run { me.progress = Progress(done: done, total: total); board.endAction(ids[done - 1]) }
            })
        ids.forEach(board.endAction)
        progress = nil
        // What went through leaves the pick; what failed or never ran stays, to be retried.
        board.select(result.failed.map(\.ticketId) + result.notRun)
        var line = appFormat("leaderBulkDone", "%1$@: %2$@ done, %3$@ failed", Self.name(action), "\(result.succeeded.count)", "\(result.failed.count)")
        if !result.notRun.isEmpty { line += " " + appFormat("leaderBulkNotRun", "· %1$@ not run", "\(result.notRun.count)") }
        toasts?.show(line, kind: result.isClean ? .success : .error)
        if !result.failed.isEmpty {
            let failed = Set(result.failed.map(\.ticketId))
            failures = Failures(action: action, tickets: plan.tickets.filter { failed.contains($0.id) },
                                messages: Dictionary(result.failed.map { ($0.ticketId, $0.message) }, uniquingKeysWith: { a, _ in a }))
        }
    }

    static func name(_ action: ZenTaoBulkAction) -> String {
        switch action {
        case .assign: appString("assign", "Assign")
        case .priority: appString("priority", "Priority")
        case .close: appString("leaderBulkCloseName", "Close")
        }
    }
}
