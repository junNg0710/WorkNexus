import Foundation

/// Ported from: lib/core/domain/value_objects/{zentao_action,zentao_task_action_input}.dart
/// A status action on a ZenTao task, in toolbar order, and what its ZenTao form asks for.
public enum ZenTaoTaskAction: String, CaseIterable, Sendable, Hashable {
    case start, restart, pause, finish, activate, close, cancel

    /// Takes the hours worked this time (added to what is already logged).
    public var asksSpent: Bool { [.start, .restart, .finish].contains(self) }
    /// Takes the hours left.
    public var asksLeft: Bool { [.start, .restart, .activate].contains(self) }
    /// Takes who the task goes to next.
    public var asksAssignee: Bool { [.start, .restart, .finish, .activate].contains(self) }
    /// Takes when work on the task really began.
    public var asksBegin: Bool { [.start, .restart, .finish].contains(self) }
    /// Takes when work on the task really ended.
    public var asksEnd: Bool { self == .finish }
    /// Takes files to attach.
    public var asksFiles: Bool { self == .finish }
    /// The action's name in the classic URL (`task-start-{id}`).
    public var name: String { rawValue }
}

/// A file picked to attach when the bug or task is saved.
public struct DraftFile: Hashable, Sendable {
    public var name: String
    public var bytes: Data
    public init(name: String, bytes: Data) { self.name = name; self.bytes = bytes }
}

/// What a ZenTao task action sends: hours worked this time (`spent`), hours `left`, the next `assignee`, when
/// work really `began` and `ended`, `files` to attach and a `comment`. Each is used only by the actions that ask
/// for it; a nil date falls back to the task's own.
public struct ZenTaoTaskActionInput: Hashable, Sendable {
    public var spent: Double
    public var left: Double
    public var assignee: String?
    public var began: Date?
    public var ended: Date?
    public var files: [DraftFile]
    public var comment: String?
    public init(spent: Double = 0, left: Double = 0, assignee: String? = nil, began: Date? = nil,
                ended: Date? = nil, files: [DraftFile] = [], comment: String? = nil) {
        self.spent = spent; self.left = left; self.assignee = assignee; self.began = began
        self.ended = ended; self.files = files; self.comment = comment
    }
}
