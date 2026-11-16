import CoreDomain

/// Ported from: lib/features/workspace_overview/presentation/providers/dashboard_providers.dart (`myWorkSyncProvider`)
/// Fetches an account's assigned bugs and tasks. Kept for the session: the stored lists show at once and the launch
/// sync keeps them current, so revisiting the Overview must not fetch them again. A sync already in flight (like
/// the launch one) is shared, not repeated; `force` runs another one after it.
public actor SyncAssignedWork {
    private let repository: OverviewRepository
    private var inFlight: [String: Task<Outcome<Void>, Never>] = [:]
    private var started: Set<String> = []

    public init(_ repository: OverviewRepository) { self.repository = repository }

    /// Whether the session already ran (or started) a sync for `accountId`.
    public func hasStarted(_ accountId: String) -> Bool { started.contains(accountId) }

    public func callAsFunction(_ accountId: String, force: Bool = false) async -> Outcome<Void> {
        if let running = inFlight[accountId] { return await running.value }
        if !force, started.contains(accountId) { return .success(()) }
        started.insert(accountId)
        let repository = self.repository
        let task = Task { await repository.syncAssignedWork(accountId: accountId) }
        inFlight[accountId] = task
        let result = await task.value
        inFlight[accountId] = nil
        return result
    }
}
