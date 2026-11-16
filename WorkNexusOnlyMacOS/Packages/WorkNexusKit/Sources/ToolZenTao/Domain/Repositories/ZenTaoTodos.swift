/// Not in the Flutter app.
import CoreDomain

/// Personal todos on a ZenTao account.
public protocol ZenTaoTodos: Sendable {
    /// Makes the todo for the account's own user; the new todo's id when the server names it.
    func createTodo(accountId: String, todo: ZenTaoTodoDraft) async -> Outcome<Int?>
}
