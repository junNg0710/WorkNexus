import CoreDomain

/// Ported from: lib/features/workspace_overview/domain/usecases/filter_my_work.dart
/// The stored tickets of one kind assigned to the account's own user - the full list behind the dashboard - newest
/// (highest id) first. With `openOnly`, finished ones are left out. The ticket store also holds tickets synced by
/// product and sprint boards, so membership is decided by the assignee, not by how a ticket got there.
public struct FilterMyWork: Sendable {
    public init() {}

    /// Whether `t` still needs work from its assignee (core/util/ticket_open.dart).
    public static func isOpen(_ t: Ticket) -> Bool {
        let finished: Set<String> = ["done", "closed", "cancel", "resolved"]
        return t.status != .done && !finished.contains(t.providerStatus.trimmingCharacters(in: .whitespaces).lowercased())
    }

    public func callAsFunction(_ tickets: [Ticket], accountId: String, userAccount: String, kind: DashboardItemKind,
                               openOnly: Bool = false) -> [Ticket] {
        let me = userAccount.trimmingCharacters(in: .whitespaces).lowercased()
        return tickets.filter {
            $0.accountId == accountId && $0.externalType?.lowercased() == kind.rawValue
                && $0.assignee?.trimmingCharacters(in: .whitespaces).lowercased() == me && (!openOnly || Self.isOpen($0))
        }.sorted { BuildWorkQueue.id($0) > BuildWorkQueue.id($1) }
    }
}
