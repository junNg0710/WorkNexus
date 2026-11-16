import Foundation

/// What the editor views ask of whoever hosts them (`TicketEditorView` maps these onto `AppNavController`), so the
/// forms themselves never touch navigation.
struct EditorActions {
    /// Cancel / back / Esc: leave the editor.
    var close: () -> Void = {}
    /// A new ticket was saved: open it in the detail panel.
    var openTicket: (String) -> Void = { _ in }
    /// Switch to another kept draft.
    var switchTo: (TicketEditorLaunch) -> Void = { _ in }
    /// Start over with a fresh form (the task form's "Add another task").
    var startOver: (TicketEditorLaunch) -> Void = { _ in }
}
