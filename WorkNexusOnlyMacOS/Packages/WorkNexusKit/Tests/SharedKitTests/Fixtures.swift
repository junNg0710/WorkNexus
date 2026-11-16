import CoreDomain
import Foundation

/// Test fixtures shared by the SharedKit tests (ports of the `_t(...)` helpers in test/domain/*.dart).
func makeTicket(
    _ id: String, account: String = "ghP", project: String = "p1", provider: ProviderType = .github, key: String? = nil,
    status: UnifiedStatus = .todo, providerStatus: String = "", priority: Priority = .medium, title: String = "Title",
    labels: [String] = [], updated: Date? = nil, severity: Int? = nil, assignee: String? = nil, type: String? = nil,
    entity: TicketProviderEntity? = nil
) -> Ticket {
    Ticket(id: id, accountId: account, projectId: project, providerType: provider, externalKey: key ?? "1", title: title, body: "",
           priority: priority, status: status, providerStatus: providerStatus, sourceHash: "h", externalType: type, labels: labels,
           assignee: assignee, severity: severity, updatedAt: updated, providerEntity: entity)
}

func ztBug(_ id: String, providerStatus: String, resolution: String? = nil, status: UnifiedStatus = .todo, severity: Int? = nil,
           assignee: String? = nil, entity: ZenTaoBugEntity? = nil) -> Ticket {
    makeTicket(id, account: "ztB", provider: .zentao, key: id, status: status, providerStatus: providerStatus,
               labels: resolution.map { ["resolution:\($0)"] } ?? [], severity: severity, assignee: assignee, type: "Bug",
               entity: entity.map(TicketProviderEntity.zentaoBug))
}

func ztTask(_ id: String, providerStatus: String, status: UnifiedStatus = .todo) -> Ticket {
    makeTicket(id, account: "ztB", provider: .zentao, key: id, status: status, providerStatus: providerStatus, type: "Task")
}

func ids(_ tickets: [Ticket]) -> [String] { tickets.map(\.id) }
