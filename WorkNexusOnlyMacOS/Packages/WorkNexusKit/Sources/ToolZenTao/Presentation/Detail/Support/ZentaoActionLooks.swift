/// Ported from: lib/tools/zentao/presentation/detail/zentao_action_looks.dart, zentao_ticket_actions.dart (`_editorRoute`)
import CoreDomain
import CoreTools
import CoreUI
import Foundation

/// How a ZenTao action shows: its name and button icon (SF Symbol).
public struct ZentaoActionLook: Equatable {
    public var label: String
    public var icon: String
}

public enum ZentaoActionLooks {
    public static func bug(_ a: ZenTaoBugAction) -> ZentaoActionLook {
        switch a {
        case .confirm: ZentaoActionLook(label: appString("zentaoConfirm", "Confirm"), icon: "checkmark.seal")
        case .resolve: ZentaoActionLook(label: appString("resolve", "Resolve"), icon: "checkmark.circle")
        case .close: ZentaoActionLook(label: appString("close", "Close"), icon: "archivebox")
        case .activate: ZentaoActionLook(label: appString("activate", "Activate"), icon: "arrow.counterclockwise")
        }
    }

    public static func task(_ a: ZenTaoTaskAction) -> ZentaoActionLook {
        switch a {
        case .start: ZentaoActionLook(label: appString("zentaoStart", "Start"), icon: "play")
        case .restart: ZentaoActionLook(label: appString("zentaoRestart", "Continue"), icon: "play.circle")
        case .pause: ZentaoActionLook(label: appString("zentaoPause", "Pause"), icon: "pause")
        case .finish: ZentaoActionLook(label: appString("zentaoFinish", "Finish"), icon: "flag")
        case .activate: ZentaoActionLook(label: appString("activate", "Activate"), icon: "arrow.counterclockwise")
        case .close: ZentaoActionLook(label: appString("close", "Close"), icon: "archivebox")
        case .cancel: ZentaoActionLook(label: appString("zentaoCancelTask", "Cancel task"), icon: "nosign")
        }
    }

    public static func create(_ a: ZenTaoCreateAction) -> ZentaoActionLook {
        switch a {
        case .copyBug: ZentaoActionLook(label: appString("zentaoCopyBug", "Copy"), icon: "doc.on.doc")
        case .copyTask: ZentaoActionLook(label: appString("zentaoCopyTask", "Clone task"), icon: "doc.on.doc")
        case .subtask: ZentaoActionLook(label: appString("zentaoAddSubtask", "Add subtask"), icon: "arrow.triangle.branch")
        case .bugFromTask: ZentaoActionLook(label: appString("zentaoReportBug", "Report bug"), icon: "ladybug")
        }
    }

    /// The dialog title: "Finish #12".
    public static func title(_ action: String, _ key: String) -> String {
        appFormat("zentaoActionTitle", "%1$@ #%2$@", action, key)
    }

    /// The toast line once `action` has run on ticket `key`.
    public static func outcome(_ result: Outcome<Void>, action: String, key: String) -> String {
        switch result {
        case .success: appFormat("zentaoActionDone", "%1$@ #%2$@: done", action, key)
        case .failure(let f): appFormat("actionFailed", "Failed: %1$@", f.message)
        }
    }
}

/// Where a create action sends the editor: a copy of the ticket, a subtask of it, or a bug filed against a task.
public func zentaoEditorRoute(for action: ZenTaoCreateAction, ticket: Ticket) -> TicketEditorRoute {
    var execution: String?, product: String?
    switch ticket.providerEntity {
    case .zentaoTask(let t): execution = t.execution
    case .zentaoBug(let b): product = b.product; execution = b.execution
    default: break
    }
    switch action {
    case .copyBug: return .newBug(accountId: ticket.accountId, productId: product ?? "0", copyOf: ticket.externalKey)
    case .copyTask: return .newTask(accountId: ticket.accountId, executionId: execution ?? "0", copyOf: ticket.externalKey)
    case .subtask: return .newTask(accountId: ticket.accountId, executionId: execution ?? "0", parentId: ticket.externalKey)
    case .bugFromTask: return .newBug(accountId: ticket.accountId, executionId: execution, taskId: ticket.externalKey)
    }
}
