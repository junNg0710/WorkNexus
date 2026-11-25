import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/domain/value_objects/{zentao_bug_action,zentao_create_action,zentao_action_menu,task_effort}.dart
public enum ZenTaoBugAction: String, CaseIterable, Sendable, Hashable { case confirm, resolve, close, activate }

/// Something new a ZenTao bug or task can start.
public enum ZenTaoCreateAction: String, CaseIterable, Sendable, Hashable { case copyBug, copyTask, subtask, bugFromTask, taskFromBug }

/// What can be done to a ZenTao bug or task now.
public struct ZenTaoActionMenu<T: Hashable & Sendable>: Sendable, Equatable {
    public var canAssign: Bool
    public var actions: [T]
    public var primary: T?
    public init(canAssign: Bool, actions: [T], primary: T?) {
        self.canAssign = canAssign; self.actions = actions; self.primary = primary
    }
}

/// A ZenTao task's hours: estimated, logged so far, and left, plus how far along it is (`progress`, 0-1).
public struct TaskEffort: Equatable, Sendable {
    public var estimate: Double, consumed: Double, left: Double, progress: Double
    public init(estimate: Double, consumed: Double, left: Double, progress: Double) {
        self.estimate = estimate; self.consumed = consumed; self.left = left; self.progress = progress
    }
}
