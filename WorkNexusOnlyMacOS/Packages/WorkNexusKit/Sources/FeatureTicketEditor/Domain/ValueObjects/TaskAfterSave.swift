/// Ported from: lib/features/ticket_editor/presentation/widgets/task_form_fields.dart (`TaskAfterSave`)
/// Where saving a new task goes next - ZenTao's "after" choice on its create form, in the app's terms.
public enum TaskAfterSave: CaseIterable, Sendable {
    /// The saved task, in the detail panel.
    case openTask
    /// A fresh form for another task in the same execution.
    case continueAdding
    /// Back to the list the editor was opened over.
    case backToList
}
