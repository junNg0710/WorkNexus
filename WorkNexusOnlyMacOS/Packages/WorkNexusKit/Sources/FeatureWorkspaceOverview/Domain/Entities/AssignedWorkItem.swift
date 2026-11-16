import CoreDomain
import Foundation

/// Ported from: lib/features/workspace_overview/domain/entities/assigned_work_item.dart
public enum AssignedReason: Sendable, Hashable { case assignee, reviewer }

public struct AssignedWorkItem: Sendable, Hashable, Identifiable {
    public var ticketId: String
    public var provider: ProviderType
    public var displayKey: String
    public var title: String
    public var status: UnifiedStatus
    public var statusLabel: String
    public var reason: AssignedReason
    public var due: Date?
    public var updatedAt: Date?
    public var id: String { ticketId }

    public init(ticketId: String, provider: ProviderType, displayKey: String, title: String, status: UnifiedStatus,
                statusLabel: String, reason: AssignedReason, due: Date? = nil, updatedAt: Date? = nil) {
        self.ticketId = ticketId; self.provider = provider; self.displayKey = displayKey; self.title = title
        self.status = status; self.statusLabel = statusLabel; self.reason = reason; self.due = due; self.updatedAt = updatedAt
    }
}
