/// Ported from: the "New bug" / "New task" buttons of widgets/{zentao_bug_section_header,zentao_task_section_header}.dart
import CoreTools
import Foundation

extension ZentaoUIState {
    /// The editor route that files a new bug for `accountId`: into the product the Bugs board has open for that
    /// account (the scope the user is looking at), else ZenTao's current one (`"0"`). Used by the Bugs header's button
    /// and by the shell's "+" menu / Cmd-N, so both open the editor on the scope in view.
    public func newBugRoute(accountId: String) -> TicketEditorRoute {
        .newBug(accountId: accountId, productId: product?.accountId == accountId ? product?.productId ?? "0" : "0")
    }

    /// The editor route that files a new task for `accountId`: into the execution the Tasks board has open for that
    /// account, else ZenTao's current one (`"0"`).
    public func newTaskRoute(accountId: String) -> TicketEditorRoute {
        .newTask(accountId: accountId, executionId: execution?.accountId == accountId ? execution?.executionId ?? "0" : "0")
    }
}
