import CoreDomain

/// What a team leader's bulk action does to one ticket. Each call is one ticket's whole job: it writes to ZenTao and
/// refreshes the ticket in the local store, or fails with the reason.
public protocol ZenTaoBulkTicketOps: Sendable {
    func assign(_ ticket: Ticket, to login: String) async -> Outcome<Void>
    /// Sets ZenTao's priority (1 urgent ... 4 low) and keeps every other field as it is.
    func setPriority(_ ticket: Ticket, to pri: Int) async -> Outcome<Void>
    func close(_ ticket: Ticket) async -> Outcome<Void>
}
