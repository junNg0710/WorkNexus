/// Not in the Flutter app.
import CoreDomain
import Foundation

/// Makes a personal todo: the name is trimmed and required, the priority kept within ZenTao's 1…4.
public struct CreateZenTaoTodo: Sendable {
    private let todos: ZenTaoTodos
    public init(_ todos: ZenTaoTodos) { self.todos = todos }

    /// The draft as it would be sent, or nil while it cannot be (no name).
    public static func ready(_ draft: ZenTaoTodoDraft) -> ZenTaoTodoDraft? {
        var out = draft
        out.name = String(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ZenTaoTodoDraft.nameLimit))
        out.desc = draft.desc.trimmingCharacters(in: .whitespacesAndNewlines)
        out.pri = min(max(draft.pri, ZenTaoTodoDraft.priorities.lowerBound), ZenTaoTodoDraft.priorities.upperBound)
        return out.name.isEmpty ? nil : out
    }

    public func callAsFunction(accountId: String, _ draft: ZenTaoTodoDraft) async -> Outcome<Int?> {
        guard let todo = Self.ready(draft) else { return .failure(.validation("A todo needs a name")) }
        return await todos.createTodo(accountId: accountId, todo: todo)
    }
}
