import CoreDomain
import Foundation

/// Ported from: lib/features/workspace_overview/presentation/util/open_dashboard_item.dart (+ core/navigation/open_zentao_ticket.dart)
/// Resolves ZenTao `kind` `id` of `account` to a ticket id the detail panel can open, fetching it from ZenTao first
/// when the board has not synced it. Todos are personal and have no detail view.
public struct OpenDashboardItem: Sendable {
    private let repository: OverviewRepository
    public init(_ repository: OverviewRepository) { self.repository = repository }

    public func callAsFunction(account: Account, kind: DashboardItemKind, id: String) async -> Outcome<String> {
        guard kind.isTicket else { return .failure(.notFound("Todos have no detail view")) }
        let host = URL(string: account.baseUrl ?? "")?.host ?? ""
        return await repository.resolveZenTaoTicket(host: host, type: kind.rawValue, id: id)
    }
}
