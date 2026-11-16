import Foundation

/// Ported from: lib/core/domain/entities/ticket.dart
public struct Ticket: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var accountId: String
    public var projectId: String
    public var providerType: ProviderType
    public var externalKey: String
    public var title: String
    public var body: String
    public var priority: Priority
    public var status: UnifiedStatus
    public var providerStatus: String
    public var sourceHash: String
    public var externalType: String?
    public var labels: [String]
    public var assignee: String?
    public var url: String?
    public var severity: Int?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var providerEntity: TicketProviderEntity?

    public init(
        id: String, accountId: String, projectId: String, providerType: ProviderType, externalKey: String,
        title: String, body: String, priority: Priority, status: UnifiedStatus, providerStatus: String,
        sourceHash: String, externalType: String? = nil, labels: [String] = [], assignee: String? = nil,
        url: String? = nil, severity: Int? = nil, createdAt: Date? = nil, updatedAt: Date? = nil,
        providerEntity: TicketProviderEntity? = nil
    ) {
        self.id = id; self.accountId = accountId; self.projectId = projectId; self.providerType = providerType
        self.externalKey = externalKey; self.title = title; self.body = body; self.priority = priority
        self.status = status; self.providerStatus = providerStatus; self.sourceHash = sourceHash
        self.externalType = externalType; self.labels = labels; self.assignee = assignee; self.url = url
        self.severity = severity; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.providerEntity = providerEntity
    }
}
