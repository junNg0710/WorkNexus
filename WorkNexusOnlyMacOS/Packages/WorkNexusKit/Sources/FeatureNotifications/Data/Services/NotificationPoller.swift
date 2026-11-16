import Foundation

/// Ported from: lib/features/notifications/presentation/providers/notification_providers.dart (`Timer.periodic`)
/// A Task-based periodic scheduler: ZenTao's own bell polls too, so the rail badge stays current. `sleep` is
/// injectable so tests drive the ticks by hand.
public final class NotificationPoller: @unchecked Sendable {
    /// Polling period of the Flutter app (`_pollEvery`).
    public static let defaultInterval: Duration = .seconds(120)

    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init(interval: Duration = NotificationPoller.defaultInterval,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.interval = interval; self.sleep = sleep
    }

    public var isRunning: Bool { lock.withLock { task != nil } }

    /// Calls `tick` every `interval` until `stop()`. Idempotent. The first tick comes after one interval: the
    /// caller refreshes once on its own when it starts.
    public func start(_ tick: @escaping @Sendable () async -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard task == nil else { return }
        let interval = interval, sleep = sleep
        task = Task {
            while !Task.isCancelled {
                do { try await sleep(interval) } catch { return }
                if Task.isCancelled { return }
                await tick()
            }
        }
    }

    public func stop() {
        lock.lock(); let t = task; task = nil; lock.unlock()
        t?.cancel()
    }

    deinit { task?.cancel() }
}
