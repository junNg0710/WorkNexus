/// Not in the Flutter app.
import CoreDomain
import Foundation

/// `ZenTaoTodos` over REST v1 (`POST /todos`), through the account's pooled client.
public struct ZenTaoTodoService: ZenTaoTodos {
    private let clients: ZenTaoClientProvider
    public init(clients: ZenTaoClientProvider) { self.clients = clients }

    public func createTodo(accountId: String, todo: ZenTaoTodoDraft) async -> Outcome<Int?> {
        guard let client = await clients.zenTaoClient(accountId: accountId) else { return .failure(.auth("ZenTao account is not signed in")) }
        // A plain todo of the user's own ("custom"), on a day and without a time of day (ZenTao then keeps it as all-day).
        let fields: JSON = ["name": todo.name, "type": "custom", "date": Self.day(todo.date), "pri": todo.pri,
                            "desc": todo.descHtml, "status": "wait"]
        do { return .success(try await client.createTodo(fields: fields)) }
        catch let e as ZenTaoError { return .failure(e.workflowFailure) }
        catch { return .failure(.network("ZenTao request failed")) }
    }

    /// `yyyy-MM-dd` in the user's calendar day.
    static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
