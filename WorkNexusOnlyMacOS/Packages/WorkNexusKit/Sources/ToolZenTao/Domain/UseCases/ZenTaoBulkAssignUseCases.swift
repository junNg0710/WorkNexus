/// Not in the Flutter app: who a leader can hand many tickets to, and how to hand them back.
import CoreDomain
import Foundation

/// The people of the teams picked tickets belong to: a task is assigned within its execution, a bug within its product.
public struct ZenTaoAssignTeams: Equatable, Sendable {
    /// Team key (`ZenTaoAssignTeams.key`) -> the logins on it, for the teams that were read.
    public var members: [String: Set<String>]
    public init(members: [String: Set<String>] = [:]) { self.members = members }

    /// The team a ticket is assigned within, or nil when ZenTao did not say.
    public static func key(_ ticket: Ticket) -> String? {
        func id(_ s: String?) -> String? {
            let v = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty || v == "0" ? nil : v
        }
        switch ticket.providerEntity {
        case .zentaoTask(let t)?: return id(t.execution).map { "e:\(ticket.accountId):\($0)" }
        case .zentaoBug(let b)?: return id(b.product).map { "p:\(ticket.accountId):\($0)" }
        default: return nil
        }
    }

    /// Whether `login` may hold `ticket`; yes when its team is unknown (ZenTao has the last word).
    public func canTake(_ ticket: Ticket, _ login: String) -> Bool {
        guard let key = Self.key(ticket), let team = members[key] else { return true }
        return team.contains(login)
    }
}

/// One person a bulk assign can go to, with what they hold already.
public struct ZenTaoBulkAssignee: Equatable, Sendable, Identifiable {
    public var login: String
    public var name: String
    public var open: Int
    public var overdue: Int
    public var pinned: Bool
    /// How many of the picked tickets they are not on the team of.
    public var cannotTake: Int
    public var id: String { login }
}

/// The people the picked tickets can go to: everyone on any of their teams (or `fallback`, the account's users, when
/// no team could be read), with their load on the board. Those who can take every ticket come first; within that,
/// the pinned people in the leader's order, then by name.
public struct ListBulkAssignees: Sendable {
    public init() {}

    public func callAsFunction(tickets: [Ticket], teams: [String: [ProviderUser]], fallback: [ProviderUser],
                               workload: [ZenTaoWorkload], pinned: [String]) -> [ZenTaoBulkAssignee] {
        var people: [ProviderUser] = []
        var seen: Set<String> = []
        for user in (teams.isEmpty ? fallback : teams.keys.sorted().flatMap { teams[$0] ?? [] }) where seen.insert(user.account).inserted {
            people.append(user)
        }
        let assignTeams = ZenTaoAssignTeams(members: teams.mapValues { Set($0.map(\.account)) })
        let load = Dictionary(workload.map { ($0.login, $0) }, uniquingKeysWith: { a, _ in a })
        let order = Dictionary(pinned.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let rows = people.map { u in
            ZenTaoBulkAssignee(login: u.account, name: u.displayName.isEmpty ? u.account : u.displayName,
                               open: load[u.account]?.open ?? 0, overdue: load[u.account]?.overdue ?? 0,
                               pinned: order[u.account] != nil,
                               cannotTake: tickets.filter { !assignTeams.canTake($0, u.account) }.count)
        }
        return rows.sorted { a, b in
            if (a.cannotTake == 0) != (b.cannotTake == 0) { return a.cannotTake == 0 }
            switch (order[a.login], order[b.login]) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }
}

/// Handing tickets back to whoever held them before a bulk assign.
public struct ZenTaoBulkUndo: Equatable, Sendable {
    /// One assign run per former holder, in the order the tickets were picked.
    public struct Step: Equatable, Sendable {
        public var login: String
        public var tickets: [Ticket]
    }

    public var steps: [Step]
    /// Tickets nobody held before: ZenTao has no assigning to nobody, so they stay where they went.
    public var cannotUndo: [Ticket]
    public var isEmpty: Bool { steps.isEmpty }
}

/// What undoing a bulk assign does: `before` are the tickets as they were, `succeeded` the ids the assign changed.
public struct PlanBulkUndo: Sendable {
    public init() {}

    public func callAsFunction(before: [Ticket], succeeded: [String]) -> ZenTaoBulkUndo {
        let done = Set(succeeded)
        var steps: [ZenTaoBulkUndo.Step] = []
        var cannot: [Ticket] = []
        for t in before where done.contains(t.id) {
            let login = (t.assignee ?? "").trimmingCharacters(in: .whitespaces)
            if login.isEmpty || login.lowercased() == "closed" { cannot.append(t); continue }
            if let i = steps.firstIndex(where: { $0.login == login }) { steps[i].tickets.append(t) }
            else { steps.append(.init(login: login, tickets: [t])) }
        }
        return ZenTaoBulkUndo(steps: steps, cannotUndo: cannot)
    }
}
