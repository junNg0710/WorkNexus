import CoreDomain

/// Ported from: lib/features/workspace_overview/domain/usecases/group_my_work.dart
/// One status section of a "my work" list.
public struct MyWorkGroup: Sendable, Equatable, Identifiable {
    public var status: UnifiedStatus
    public var tickets: [Ticket]
    public var id: UnifiedStatus { status }
    public init(status: UnifiedStatus, tickets: [Ticket]) { self.status = status; self.tickets = tickets }
}

/// Splits a "my work" list into status sections, ordered by what needs the assignee first: work in progress, then
/// what is still to start, then what is waiting on someone else, then finished. Inside a section the most urgent
/// comes first, then the newest.
public struct GroupMyWork: Sendable {
    public init() {}
    private static let order: [UnifiedStatus] = [.inprogress, .todo, .inbox, .blocked, .review, .done]

    public func callAsFunction(_ tickets: [Ticket]) -> [MyWorkGroup] {
        var byStatus: [UnifiedStatus: [Ticket]] = [:]
        for t in tickets { byStatus[t.status, default: []].append(t) }
        return Self.order.compactMap { status in
            byStatus[status].map { MyWorkGroup(status: status, tickets: $0.sorted(by: Self.byUrgency)) }
        }
    }

    private static func byUrgency(_ a: Ticket, _ b: Ticket) -> Bool {
        if a.priority.level != b.priority.level { return a.priority.level < b.priority.level }
        return BuildWorkQueue.id(a) > BuildWorkQueue.id(b)
    }
}
