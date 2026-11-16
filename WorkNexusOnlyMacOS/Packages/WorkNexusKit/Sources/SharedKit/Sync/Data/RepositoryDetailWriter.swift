import CoreDomain
import Foundation

/// Default `DetailWriting` built on the `CoreDomain` repositories. Limits (use a database-backed writer for exact
/// Flutter behaviour): replacement is an upsert (comments/events deleted on the server stay until the next clear),
/// and `overwrite` goes through `upsertTickets` + `moveTicket`, so a changed `sourceHash` or `status` is written.
public struct RepositoryDetailWriter: DetailWriting {
    let tickets: TicketRepository
    let comments: CommentRepository
    let activity: ActivityRepository

    public init(tickets: TicketRepository, comments: CommentRepository, activity: ActivityRepository) {
        self.tickets = tickets; self.comments = comments; self.activity = activity
    }

    public func replaceProviderComments(ticketId: String, comments fresh: [Comment]) async -> Outcome<Void> {
        await comments.upsertComments(fresh)
    }

    public func replaceActivity(ticketId: String, events: [ActivityEvent]) async -> Outcome<Void> {
        await activity.upsertActivity(events)
    }

    public func overwrite(ticket: Ticket) async -> Outcome<Void> {
        if case .failure(let f) = await tickets.upsertTickets([ticket]) { return .failure(f) }
        return await tickets.moveTicket(id: ticket.id, to: ticket.status)
    }
}
