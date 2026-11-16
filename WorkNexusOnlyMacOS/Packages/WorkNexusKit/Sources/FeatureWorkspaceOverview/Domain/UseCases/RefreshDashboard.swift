import CoreDomain
import Foundation

/// Ported from: lib/features/workspace_overview/domain/usecases/refresh_dashboard.dart
/// Brings an account's dashboard up to date. Opening the dashboard calls it unforced, so a snapshot younger than
/// `maxAge` is shown as is instead of hitting the server on every visit; the refresh button forces it.
public struct RefreshDashboard: Sendable {
    private let repository: OverviewRepository
    public let maxAge: TimeInterval
    private let now: @Sendable () -> Date

    public init(_ repository: OverviewRepository, maxAge: TimeInterval = 5 * 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository; self.maxAge = maxAge; self.now = now
    }

    public func callAsFunction(_ accountId: String, force: Bool = false) async -> Outcome<Void> {
        if !force, let cached = await repository.cachedDashboard(accountId: accountId), now().timeIntervalSince(cached.fetchedAt) < maxAge {
            return .success(())
        }
        return await repository.refreshDashboard(accountId: accountId)
    }
}
