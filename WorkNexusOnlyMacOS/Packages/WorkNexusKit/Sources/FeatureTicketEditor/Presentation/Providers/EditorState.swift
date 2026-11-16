import CoreDomain
import Foundation

/// Ported from: lib/features/ticket_editor/presentation/providers/ticket_editor_state.dart
/// A bug being added or edited: the form as loaded and the draft as changed.
public struct BugEditorState {
    public var form: BugForm
    public var draft: BugDraft
    /// Ties the images uploaded into the steps to the bug when it is saved.
    public var uid: String
    public var saving = false
    public var missing: Set<DraftField> = []
    /// Why the last save failed.
    public var failure: Failure?
    /// The kept draft of a new bug (nil when editing one), and when it was last kept (nil until something was written).
    public var draftId: String?
    public var draftSavedAt: Date?
}

/// A task being added or edited.
public struct TaskEditorState {
    public var form: TaskForm
    public var draft: TaskDraft
    public var uid: String
    public var saving = false
    public var missing: Set<DraftField> = []
    public var failure: Failure?
    public var draftId: String?
    public var draftSavedAt: Date?
}
