/// Ported from: the state logic of lib/tools/zentao/presentation/detail/zentao_task_action_dialog.dart
import CoreDomain
import Foundation

/// What a ZenTao task action's form holds, and what it sends: the hours worked and left, who the task goes to next,
/// when work really began and ended, files. Pure, so the dialog's rules are testable without a view.
struct ZentaoTaskActionForm: Equatable {
    let action: ZenTaoTaskAction
    let task: ZenTaoTaskEntity?
    let ticketAssignee: String?
    var spent = ""
    var left: String
    var assignee: String?
    var began: Date
    var ended: Date
    var files: [DraftFile] = []

    init(ticket: Ticket, action: ZenTaoTaskAction, now: Date = Date()) {
        self.action = action
        if case .zentaoTask(let t) = ticket.providerEntity { task = t } else { task = nil }
        ticketAssignee = ticket.assignee
        // A task keeps its hours left until it is finished, so they are offered again; a finished task has none left,
        // to be filled in on reopening.
        if let l = task?.left, l > 0 { left = zentaoHoursText(l) } else { left = "" }
        // Preset as ZenTao's forms are: starting keeps the task with its holder, finishing hands it back to its creator.
        switch action {
        case .finish: assignee = task?.openedByHandle
        case .start, .restart: assignee = ticket.assignee
        default: assignee = nil
        }
        // One "now" for both, so the default end is never before the begin.
        began = task?.realStarted ?? now
        ended = began > now ? began : now
    }

    /// Hours already logged on the task.
    var logged: Double { task?.consumed ?? 0 }
    /// Finishing keeps a begin that is already recorded, as ZenTao does.
    var beginEditable: Bool { !action.asksEnd || task?.realStarted == nil }

    func input(comment: String?) -> ZenTaoTaskActionInput {
        ZenTaoTaskActionInput(spent: zentaoParseHours(spent), left: zentaoParseHours(left), assignee: assignee,
                              began: action.asksBegin ? began : nil, ended: action.asksEnd ? ended : nil,
                              files: files, comment: comment)
    }

    /// Why ZenTao would refuse this input; nil when it is fine.
    var problem: ZenTaoTaskInputProblem? {
        CheckZenTaoTaskInput()(action: action, input: input(comment: nil), logged: logged)
    }

    /// ZenTao's "already cost / total cost": the total follows the hours typed for this time.
    var hoursHint: String {
        guard action.asksSpent else { return "" }
        let s = zentaoParseHours(spent)
        var parts: [String] = []
        if logged > 0 { parts.append(zentaoHoursLoggedText(logged)) }
        if s > 0, !s.isNaN { parts.append(zentaoHoursTotalText(logged + s)) }
        return parts.joined(separator: " · ")
    }
}
