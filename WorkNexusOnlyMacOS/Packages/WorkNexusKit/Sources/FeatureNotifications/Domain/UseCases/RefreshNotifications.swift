import CoreDomain
import Foundation

/// Ported from: lib/features/notifications/domain/usecases/refresh_notifications.dart
/// Refreshes the notifications of several accounts at once. One account failing does not stop the others; the
/// first failure is returned.
public struct RefreshNotifications: Sendable {
    private let repository: ZenTaoNotificationRepository
    public init(_ repository: ZenTaoNotificationRepository) { self.repository = repository }

    public func callAsFunction(_ accountIds: [String]) async -> Outcome<Void> {
        let results = await withTaskGroup(of: (Int, Outcome<Void>).self) { group in
            for (i, id) in accountIds.enumerated() { group.addTask { (i, await repository.refresh(accountId: id)) } }
            var out: [(Int, Outcome<Void>)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        for r in results { if case .failure(let f) = r { return .failure(f) } }
        return .success(())
    }
}
