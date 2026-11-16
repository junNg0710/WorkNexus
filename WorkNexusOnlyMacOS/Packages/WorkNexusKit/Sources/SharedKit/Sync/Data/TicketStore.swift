import CoreDomain
import Foundation

/// Ported from: lib/shared/sync/data/ticket_store.dart
/// Writes what a sync fetched into the ticket tables — only the rows that differ from what is stored. Every write
/// re-runs the DB watches over its table (the board, every card, the open panel), so a page or a refresh that
/// brings nothing new must leave the tables untouched. Rows are compared in their stored form (`StoredForm`).
public struct TicketStore: Sendable {
    let tickets: TicketRepository
    let workspaces: WorkspaceRepository
    let comments: CommentRepository
    let activity: ActivityRepository
    let writer: DetailWriting

    public init(tickets: TicketRepository, workspaces: WorkspaceRepository, comments: CommentRepository,
                activity: ActivityRepository, writer: DetailWriting? = nil) {
        self.tickets = tickets; self.workspaces = workspaces; self.comments = comments; self.activity = activity
        self.writer = writer ?? RepositoryDetailWriter(tickets: tickets, comments: comments, activity: activity)
    }

    /// The stored tickets among `ids`, by id.
    public func stored(_ ids: [String]) async -> [String: Ticket] {
        var out: [String: Ticket] = [:]
        for id in ids {
            if case .success(let t?) = await tickets.ticket(id: id) { out[id] = t }
        }
        return out
    }

    /// Stores `account`, the projects its `tickets` name, and the tickets a list sync fetched. Carries forward the
    /// synthetic board-membership labels already stored for these tickets (each list sync stamps only its own marker).
    public func writeSynced(_ account: Account, _ fetched: [Ticket]) async {
        let prior = await stored(fetched.map(\.id))
        var changed: [Ticket] = []
        for t in fetched {
            var merged = t
            if let s = prior[t.id] { merged.labels = mergeDetailLabels(t.labels, s.labels) }
            if prior[t.id] != StoredForm.ticket(merged) { changed.append(merged) }
        }
        var projects: [String: Project] = [:]
        for t in fetched where projects[t.projectId] == nil {
            projects[t.projectId] = Project(id: t.projectId, accountId: account.id,
                                            name: t.projectId.split(separator: ":", omittingEmptySubsequences: false).dropFirst().joined(separator: ":"))
        }
        let storedProjects = Dictionary(((await firstValue(of: workspaces.watchProjects())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let changedProjects = projects.values.filter { storedProjects[$0.id] != $0 }
        let storedAccount = ((await firstValue(of: workspaces.watchAccounts())) ?? []).first { $0.id == account.id }
        let accountChanged = storedAccount != account
        if accountChanged { _ = await workspaces.upsertAccount(account) }
        if !changedProjects.isEmpty { _ = await workspaces.upsertProjects(Array(changedProjects)) }
        if !changed.isEmpty { _ = await tickets.upsertTickets(changed) }
    }

    /// Stores `ticket` unless its row already reads the same (compared against the row, not the caller's copy: after
    /// an optimistic update the row holds the guess, and the server's answer must replace it).
    public func writeIfChanged(_ ticket: Ticket) async {
        let prior = (await stored([ticket.id]))[ticket.id]
        if prior == StoredForm.ticket(ticket) { return }
        _ = await writer.overwrite(ticket: ticket)
    }

    /// Replaces the provider's comments on `ticketId` with `fresh` (internal notes stay), unless the stored set matches.
    public func replaceProviderComments(_ ticketId: String, _ fresh: [Comment]) async {
        guard await commentsDiffer(ticketId, fresh) else { return }
        _ = await writer.replaceProviderComments(ticketId: ticketId, comments: fresh)
    }

    /// Replaces the activity of `ticketId` with `events`, unless the stored set already matches.
    public func replaceActivity(_ ticketId: String, _ events: [ActivityEvent]) async {
        guard await activityDiffers(ticketId, events) else { return }
        _ = await writer.replaceActivity(ticketId: ticketId, events: events)
    }

    /// A detail refresh's comments and activity in one write: only the lists that differ from what is stored are replaced,
    /// and both go in together (nil = that fetch failed, leave the stored list alone).
    public func replaceDetail(_ ticketId: String, comments fresh: [Comment]?, activity events: [ActivityEvent]?) async {
        let newComments = if let fresh { await commentsDiffer(ticketId, fresh) ? fresh : nil } else { [Comment]?.none }
        let newEvents = if let events { await activityDiffers(ticketId, events) ? events : nil } else { [ActivityEvent]?.none }
        guard newComments != nil || newEvents != nil else { return }
        _ = await writer.replaceDetail(ticketId: ticketId, comments: newComments, events: newEvents)
    }

    private func commentsDiffer(_ ticketId: String, _ fresh: [Comment]) async -> Bool {
        let all = (await firstValue(of: comments.watchComments(ticketId: ticketId))) ?? []
        let prior = Dictionary(all.filter { $0.origin == .provider }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let next = Dictionary(fresh.map { ($0.id, StoredForm.comment($0)) }, uniquingKeysWith: { a, _ in a })
        return prior != next
    }

    private func activityDiffers(_ ticketId: String, _ events: [ActivityEvent]) async -> Bool {
        let all = (await firstValue(of: activity.watchActivity(ticketId: ticketId))) ?? []
        let prior = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let next = Dictionary(events.map { ($0.id, StoredForm.activity($0)) }, uniquingKeysWith: { a, _ in a })
        return prior != next
    }
}
