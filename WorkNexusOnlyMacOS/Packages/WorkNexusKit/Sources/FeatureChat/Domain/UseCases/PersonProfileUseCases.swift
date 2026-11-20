/// Ported from: lib/features/chat/domain/usecases/{find_shared_groups,list_person_tickets}.dart
import CoreDomain
import Foundation

/// The group chats the signed-in user shares with user `userId`, most recently active first. xxd keeps no membership
/// locally, so each group's members are asked of the server, a few at a time. A group that fails to answer is skipped;
/// only when every group fails is the failure returned.
public struct FindSharedGroups: Sendable {
    private let repository: ChatRepository
    /// How many member lists are asked for at once.
    private let parallel: Int
    public init(_ repository: ChatRepository, parallel: Int = 6) { self.repository = repository; self.parallel = parallel }

    public func callAsFunction(accountId: String, userId: Int) async -> Outcome<[ChatConversation]> {
        var it = repository.watchConversations(accountId: accountId).makeAsyncIterator()
        let groups = (await it.next() ?? []).filter { $0.type == .group && !$0.archived }
        var shared: [ChatConversation] = []
        var failure: Failure?
        var answered = 0
        var start = 0
        while start < groups.count {
            let batch = Array(groups[start..<min(start + parallel, groups.count)])
            let replies = await withTaskGroup(of: (Int, Outcome<[Int]>).self) { group in
                for (i, g) in batch.enumerated() { group.addTask { (i, await repository.members(accountId: accountId, chatGid: g.gid)) } }
                var out: [(Int, Outcome<[Int]>)] = []
                for await r in group { out.append(r) }
                return out.sorted { $0.0 < $1.0 }
            }
            for (i, reply) in replies {
                switch reply {
                case .success(let members): answered += 1; if members.contains(userId) { shared.append(batch[i]) }
                case .failure(let f): failure = failure ?? f
                }
            }
            start += parallel
        }
        if answered == 0, let failure { return .failure(failure) }
        return .success(shared.sorted { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) })
    }
}

/// A person's open synced tickets: those assigned to them, and those they reported that someone else now holds.
public struct PersonTickets: Equatable, Sendable {
    public var assigned: [Ticket]
    public var reported: [Ticket]
    public var count: Int { assigned.count + reported.count }
    public init(assigned: [Ticket] = [], reported: [Ticket] = []) { self.assigned = assigned; self.reported = reported }
}

/// Picks the open tickets of ZenTao user `handle` on account `accountId` from the synced `tickets`, most recently updated
/// first. Handles compare without case: ZenTao logins are case-insensitive.
public struct ListPersonTickets: Sendable {
    public init() {}

    public func callAsFunction(_ tickets: [Ticket], accountId: String, handle: String) -> PersonTickets {
        let who = handle.trimmingCharacters(in: .whitespaces).lowercased()
        guard !who.isEmpty else { return PersonTickets() }
        var out = PersonTickets()
        for t in tickets where t.accountId == accountId && t.status != .done {
            if t.assignee?.lowercased() == who { out.assigned.append(t) }
            else if Self.openedBy(t)?.lowercased() == who { out.reported.append(t) }
        }
        func newestFirst(_ a: Ticket, _ b: Ticket) -> Bool {
            (a.updatedAt ?? a.createdAt ?? .distantPast) > (b.updatedAt ?? b.createdAt ?? .distantPast)
        }
        out.assigned.sort(by: newestFirst)
        out.reported.sort(by: newestFirst)
        return out
    }

    private static func openedBy(_ t: Ticket) -> String? {
        switch t.providerEntity {
        case .zentaoBug(let b)?: b.openedByHandle
        case .zentaoTask(let task)?: task.openedByHandle
        default: nil
        }
    }
}
