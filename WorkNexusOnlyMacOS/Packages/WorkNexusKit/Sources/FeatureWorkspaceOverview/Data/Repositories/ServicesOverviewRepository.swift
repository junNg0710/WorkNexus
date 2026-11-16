import CoreDomain
import CoreTools

/// Reads and drives the overview through the app's `AppServices` (the composition root's wiring): tickets, accounts
/// and workspaces from the local database, the ZenTao dashboard through the hoisted `ZenTaoDashboardRepository`
/// (`services.zentaoDashboard`) and ticket resolution through `ZenTaoTicketService` (`services.zentaoTickets`).
/// Without those hooks (no ZenTao account wired) the streams are empty and the commands fail with `.unexpected`.
public struct ServicesOverviewRepository: OverviewRepository {
    private let services: AppServices
    public init(services: AppServices) { self.services = services }

    public func watchWorkspaces() -> AsyncStream<[Workspace]> { services.workspaces.watchWorkspaces() }
    public func watchAccounts() -> AsyncStream<[Account]> { services.workspaces.watchAccounts() }
    public func watchTickets() -> AsyncStream<[Ticket]> { services.tickets.watchTickets() }
    public func watchDateFormat() -> AsyncStream<String> {
        let settings = services.settings.watch()
        return AsyncStream { continuation in
            let task = Task {
                for await s in settings { continuation.yield(s.dateFormat) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func watchDashboard(accountId: String) -> AsyncStream<ZenTaoDashboard?> {
        services.zentaoDashboard?.watch(accountId: accountId) ?? AsyncStream { $0.yield(nil); $0.finish() }
    }
    public func cachedDashboard(accountId: String) async -> ZenTaoDashboard? { await services.zentaoDashboard?.cached(accountId: accountId) }

    public func refreshDashboard(accountId: String) async -> Outcome<Void> {
        guard let dashboard = services.zentaoDashboard else { return .failure(.unexpected("ZenTao dashboard is not wired")) }
        return await dashboard.refresh(accountId: accountId)
    }
    public func syncAssignedWork(accountId: String) async -> Outcome<Void> {
        guard let dashboard = services.zentaoDashboard else { return .failure(.unexpected("ZenTao dashboard is not wired")) }
        return await dashboard.syncAssignedWork(accountId: accountId)
    }
    public func resolveZenTaoTicket(host: String, type: String, id: String) async -> Outcome<String> {
        guard let tickets = services.zentaoTickets else { return .failure(.unexpected("ZenTao tickets are not wired")) }
        return await tickets.fetchZenTaoTicket(host: host, type: type, id: id)
    }
}
