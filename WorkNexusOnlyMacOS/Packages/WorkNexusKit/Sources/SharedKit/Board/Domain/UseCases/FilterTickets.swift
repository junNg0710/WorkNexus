import CoreDomain
import Foundation

/// Ported from: lib/shared/board/domain/usecases/filter_tickets.dart
/// Everything `FilterTickets` / `BuildBoard` need: tickets, the active filter, which workspace each account belongs to.
public struct BoardQuery: Equatable, Sendable {
    public var tickets: [Ticket]
    public var filter: FilterState
    public var accountWorkspace: [String: String]
    public var now: Date
    public var workspaceOrder: [String]
    public var accounts: [String: Account]
    /// The order of the cards within each board column.
    public var sort: TicketSort
    public init(tickets: [Ticket], filter: FilterState, accountWorkspace: [String: String], now: Date,
                workspaceOrder: [String] = [], accounts: [String: Account] = [:], sort: TicketSort = .boardDefault) {
        self.tickets = tickets; self.filter = filter; self.accountWorkspace = accountWorkspace; self.now = now
        self.workspaceOrder = workspaceOrder; self.accounts = accounts; self.sort = sort
    }
    public func withFilter(_ filter: FilterState) -> BoardQuery {
        BoardQuery(tickets: tickets, filter: filter, accountWorkspace: accountWorkspace, now: now,
                   workspaceOrder: workspaceOrder, accounts: accounts, sort: sort)
    }
}

/// Predicate behind each built-in saved view.
public func savedViewMatches(_ view: SavedView, _ t: Ticket, _ now: Date, _ account: Account? = nil) -> Bool {
    func closed() -> Bool { t.status == .done || t.providerStatus.trimmingCharacters(in: .whitespaces).lowercased() == "closed" }
    switch view {
    case .all: return true
    case .today:
        guard let u = t.updatedAt else { return false }
        return abs(now.timeIntervalSince(u)) < 24 * 3600
    case .mine:
        guard let account else { return t.status == .todo || t.status == .inprogress }
        return !closed() && IsAssignedToMe()(t, account)
    case .related:
        guard let account else { return t.status == .todo || t.status == .inprogress }
        return !closed() && IsRelatedToMe()(t, account)
    case .review: return t.status == .review
    case .blocked: return t.status == .blocked
    }
}

/// Applies a `FilterState` to a ticket list.
public struct FilterTickets: Sendable {
    public init() {}

    private func resolveAccount(_ q: BoardQuery, _ t: Ticket) -> Account? {
        if let a = q.accounts[t.accountId] { return a }
        return q.accounts.values.first { $0.providerType == t.providerType }
    }

    public func callAsFunction(_ q: BoardQuery) -> [Ticket] {
        let f = q.filter
        let query = f.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.tickets.filter { t in
            if f.workspaceId != "all", q.accountWorkspace[t.accountId] != f.workspaceId { return false }
            if !savedViewMatches(f.savedView, t, q.now, resolveAccount(q, t)) { return false }
            if !f.providers.isEmpty, !f.providers.contains(t.providerType) { return false }
            if !f.accountIds.isEmpty, !f.accountIds.contains(t.accountId) { return false }
            if !f.projectIds.isEmpty, !f.projectIds.contains(t.projectId) { return false }
            if !f.statuses.isEmpty, !f.statuses.contains(t.status) { return false }
            if !f.priorities.isEmpty, !f.priorities.contains(t.priority) { return false }
            if !f.severities.isEmpty { guard let s = t.severity, f.severities.contains(s) else { return false } }
            // The people filters ask one question — is one of these people on the ticket, in the role picked.
            if !f.assignees.isEmpty || !f.resolvers.isEmpty || !f.reporters.isEmpty {
                var bug: ZenTaoBugEntity?
                if case .zentaoBug(let e) = t.providerEntity { bug = e }
                let matches = anySelected(f.assignees, assigneeValues(t))
                    || (bug != nil && f.resolvers.contains(bug?.resolvedBy ?? ""))
                    || (bug != nil && f.reporters.contains(bug?.openedBy ?? ""))
                if !matches { return false }
            }
            if !f.reviewers.isEmpty, !anySelected(f.reviewers, reviewerValues(t)) { return false }
            if !f.bugTypes.isEmpty || !f.resolutions.isEmpty {
                var bugType = "", resolution = ""
                if case .zentaoBug(let e) = t.providerEntity {
                    bugType = (e.bugType ?? "").lowercased(); resolution = (e.resolution ?? "").lowercased()
                }
                if !f.bugTypes.isEmpty, !f.bugTypes.contains(bugType) { return false }
                if !f.resolutions.isEmpty, !f.resolutions.contains(resolution) { return false }
            }
            if !f.zentaoStatuses.isEmpty {
                guard let s = zentaoStatusOf(t), f.zentaoStatuses.contains(s) else { return false }
            }
            if !f.confirmations.isEmpty {
                guard case .zentaoBug(let e) = t.providerEntity, f.confirmations.contains("\(e.confirmed ?? 0)") else { return false }
            }
            if !f.modules.isEmpty, !f.modules.contains(zentaoModuleOf(t) ?? "") { return false }
            if !query.isEmpty {
                let hay = [t.title, t.externalKey, t.externalType ?? "", t.assignee ?? "", t.providerType.code,
                           t.labels.joined(separator: " ")].joined(separator: " ").lowercased()
                if !hay.contains(query) { return false }
            }
            return true
        }
    }

    private func anySelected(_ selected: Set<String>, _ values: [String]) -> Bool { values.contains { selected.contains($0) } }

    private func assigneeValues(_ t: Ticket) -> [String] {
        switch t.providerEntity {
        case .gitlabItem(let e) where !e.assignees.isEmpty: return e.assignees
        case .zentaoBug(let e):
            // A bug counts as "mine" if I'm the current assignee OR resolved OR opened it (ZenTao reassigns on resolve).
            // The current assignee stays first (possibly "") so the "unassigned" sentinel still works.
            var out = [t.assignee ?? ""]
            for h in [e.resolvedByHandle, e.openedByHandle] { if let h, !h.isEmpty, !out.contains(h) { out.append(h) } }
            return out
        default: return [t.assignee ?? ""]
        }
    }

    private func reviewerValues(_ t: Ticket) -> [String] {
        if case .gitlabItem(let e) = t.providerEntity, !e.reviewers.isEmpty { return e.reviewers }
        return [""]
    }
}
