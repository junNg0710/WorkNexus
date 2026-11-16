import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/domain/usecases/{check_zentao_task_input,check_zentao_assign_left,summarize_task_effort}.dart
/// Why a task action's input would be refused by ZenTao.
public enum ZenTaoTaskInputProblem: Sendable, Equatable {
    /// Hours must be a number, 0 or more.
    case invalidHours
    /// Starting, continuing or reopening needs the hours left (above 0).
    case leftRequired
    /// Finishing a task with nothing logged needs the hours worked.
    case spentRequired
    /// ZenTao refuses a finish dated before the task began.
    case endBeforeBegin
}

/// Checks a task action's input before it is sent; nil when it is fine.
public struct CheckZenTaoTaskInput: Sendable {
    public init() {}
    public func callAsFunction(action: ZenTaoTaskAction, input: ZenTaoTaskActionInput, logged: Double) -> ZenTaoTaskInputProblem? {
        var hours: [Double] = []
        if action.asksSpent { hours.append(input.spent) }
        if action.asksLeft { hours.append(input.left) }
        if hours.contains(where: { $0.isNaN || $0 < 0 }) { return .invalidHours }
        if action.asksLeft && input.left <= 0 { return .leftRequired }
        if action == .finish && input.spent <= 0 && logged <= 0 { return .spentRequired }
        if action.asksEnd, let began = input.began, let ended = input.ended, ended < began { return .endBeforeBegin }
        return nil
    }
}

/// Checks the hours left an unfinished task is assigned with: ZenTao's assign form requires them and refuses 0.
public struct CheckZenTaoAssignLeft: Sendable {
    public init() {}
    public func callAsFunction(_ left: Double) -> ZenTaoTaskInputProblem? {
        if left.isNaN || left < 0 { return .invalidHours }
        if left == 0 { return .leftRequired }
        return nil
    }
}

/// A task's hours for the detail header, or nil when it has none on record. Progress is logged over
/// logged-plus-left, as ZenTao reckons it.
public struct SummarizeTaskEffort: Sendable {
    public init() {}
    public func callAsFunction(_ task: ZenTaoTaskEntity) -> TaskEffort? {
        let estimate = hours(task.estimate), consumed = hours(task.consumed), left = hours(task.left)
        if estimate == 0 && consumed == 0 && left == 0 { return nil }
        let total = consumed + left
        return TaskEffort(estimate: estimate, consumed: consumed, left: left,
                          progress: total == 0 ? 0 : min(max(consumed / total, 0), 1))
    }
    /// Unset or nonsense hours count as none.
    private func hours(_ v: Double?) -> Double { guard let v, !v.isNaN, v >= 0 else { return 0 }; return v }
}
