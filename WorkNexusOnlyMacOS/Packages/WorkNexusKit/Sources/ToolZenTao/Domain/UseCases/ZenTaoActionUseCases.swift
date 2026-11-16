import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/domain/usecases/{list_zentao_bug_actions,list_zentao_task_actions,list_zentao_create_actions}.dart
/// The actions ZenTao offers on a bug in its current state (`bugModel::isClickable`).
public struct ListZenTaoBugActions: Sendable {
    public init() {}
    public func callAsFunction(_ ticket: Ticket) -> ZenTaoActionMenu<ZenTaoBugAction> {
        let raw = ticket.providerStatus.trimmingCharacters(in: .whitespaces).lowercased()
        let active = raw == "active"
        // An active bug sits in the inbox until it is confirmed.
        let unconfirmed = active && ticket.status == .inbox
        func offers(_ action: ZenTaoBugAction) -> Bool {
            switch action {
            case .confirm: unconfirmed
            case .resolve: active
            case .close: raw == "resolved"
            case .activate: raw == "resolved" || raw == "closed"
            }
        }
        let actions = ZenTaoBugAction.allCases.filter(offers)
        return ZenTaoActionMenu(canAssign: !raw.isEmpty && raw != "closed", actions: actions, primary: actions.first)
    }
}

/// The actions ZenTao offers on a task in its current state (`taskModel::isClickable`).
public struct ListZenTaoTaskActions: Sendable {
    public init() {}
    /// What a parent task allows in both ZenTao 18.x and 20+: its status follows its subtasks.
    private static let parentActions: Set<ZenTaoTaskAction> = [.restart, .cancel]
    /// The actions that move a task forward, most pressing first.
    private static let forward: [ZenTaoTaskAction] = [.start, .restart, .finish, .close, .activate]

    public func callAsFunction(_ ticket: Ticket) -> ZenTaoActionMenu<ZenTaoTaskAction> {
        let raw = ticket.providerStatus.trimmingCharacters(in: .whitespaces).lowercased()
        var isParent = false
        if case .zentaoTask(let t) = ticket.providerEntity { isParent = t.isParent }
        let ended = raw == "done" || raw == "closed" || raw == "cancel"
        func offers(_ action: ZenTaoTaskAction) -> Bool {
            if isParent && !Self.parentActions.contains(action) { return false }
            switch action {
            case .start: return raw == "wait"
            case .restart: return raw == "pause"
            case .pause: return raw == "doing"
            case .finish: return !raw.isEmpty && !ended
            case .activate: return ended
            case .close: return raw == "done" || raw == "cancel"
            case .cancel: return !raw.isEmpty && !ended
            }
        }
        let actions = ZenTaoTaskAction.allCases.filter(offers)
        return ZenTaoActionMenu(
            canAssign: !raw.isEmpty && raw != "closed" && raw != "cancel",
            actions: actions,
            primary: Self.forward.first { actions.contains($0) })
    }
}

/// What can be started from a ZenTao bug or task.
public struct ListZenTaoCreateActions: Sendable {
    public init() {}
    public func callAsFunction(_ ticket: Ticket) -> [ZenTaoCreateAction] {
        let raw = ticket.providerStatus.trimmingCharacters(in: .whitespaces).lowercased()
        switch (ticket.externalType ?? "").lowercased() {
        case "bug": return [.copyBug]
        case "task":
            var out: [ZenTaoCreateAction] = [.copyTask]
            if case .zentaoTask(let t) = ticket.providerEntity, t.parentId == nil, t.execution != nil,
               raw != "closed", raw != "cancel" {
                out.append(.subtask)
            }
            out.append(.bugFromTask)
            return out
        default: return []
        }
    }
}
