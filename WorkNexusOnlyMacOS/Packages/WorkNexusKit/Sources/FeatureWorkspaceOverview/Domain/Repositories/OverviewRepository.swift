import CoreDomain

/// What the overview reads and triggers, as one local-first port (the Flutter feature reads `ticketsProvider`,
/// `accountsProvider`, the dashboard repository and the ZenTao ticket resolver). The `watch*` streams read the local
/// database; the commands change it through the sync layer.
public protocol OverviewRepository: Sendable {
    func watchWorkspaces() -> AsyncStream<[Workspace]>
    func watchAccounts() -> AsyncStream<[Account]>
    func watchTickets() -> AsyncStream<[Ticket]>
    /// The app-wide date format (`AppSettings.dateFormat`: iso / dmy / long).
    func watchDateFormat() -> AsyncStream<String>
    /// The stored ZenTao dashboard of an account (nil until first fetched), live.
    func watchDashboard(accountId: String) -> AsyncStream<ZenTaoDashboard?>
    func cachedDashboard(accountId: String) async -> ZenTaoDashboard?
    func refreshDashboard(accountId: String) async -> Outcome<Void>
    /// Pulls every ticket assigned to the account into the store.
    func syncAssignedWork(accountId: String) async -> Outcome<Void>
    /// Fetches ZenTao `type` `id` from the account on `host` (when not synced yet); returns its ticket id.
    func resolveZenTaoTicket(host: String, type: String, id: String) async -> Outcome<String>
}
