import CoreDomain

/// Ported from: lib/features/workspace_overview/domain/usecases/build_work_queue.dart
/// The user's open work, split the way they act on it: what is already in progress, then what has not been started.
public struct WorkQueue: Sendable, Equatable {
    public var inProgress: [Ticket]
    public var notStarted: [Ticket]
    public init(inProgress: [Ticket] = [], notStarted: [Ticket] = []) { self.inProgress = inProgress; self.notStarted = notStarted }
    public var isEmpty: Bool { inProgress.isEmpty && notStarted.isEmpty }
    public var count: Int { inProgress.count + notStarted.count }
}

/// Merges open bugs and tasks into one queue. Each group is ordered by priority (most urgent first), then newest
/// first, so the next thing to pick up is on top whatever its kind.
public struct BuildWorkQueue: Sendable {
    public init() {}

    public func callAsFunction(_ openTickets: [Ticket]) -> WorkQueue {
        let sorted = openTickets.sorted { a, b in
            if a.priority.level != b.priority.level { return a.priority.level < b.priority.level }
            return Self.id(a) > Self.id(b)
        }
        return WorkQueue(inProgress: sorted.filter { $0.status == .inprogress }, notStarted: sorted.filter { $0.status != .inprogress })
    }

    static func id(_ t: Ticket) -> Int { Int(t.externalKey) ?? 0 }
}
