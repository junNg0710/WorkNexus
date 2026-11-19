/// Ported from: the Riverpod `StreamProvider` the Flutter app reads tickets through (lib/core/di/providers.dart
/// `ticketsProvider`): one database query, shared by everyone who watches it.
import Foundation

/// One observation of the database, shared by every watcher: the query runs (and its rows are decoded) once per change,
/// however many views watch it, and a new watcher gets the latest value at once instead of waiting for its own first
/// read. Each watcher keeps only the newest value it has not taken yet, so a slow one skips what it could not keep up
/// with rather than working through every intermediate list. The observation starts with the first watcher and stops
/// when the last one goes.
final class SharedObservation<T: Sendable>: @unchecked Sendable {
    private let start: @Sendable () -> AsyncStream<T>
    private let lock = NSLock()
    private var watchers: [UUID: AsyncStream<T>.Continuation] = [:]
    private var latest: T?
    private var source: Task<Void, Never>?
    /// Bumped each time the observation restarts: a value from one already stopped is dropped.
    private var generation = 0

    init(_ start: @escaping @Sendable () -> AsyncStream<T>) { self.start = start }

    func stream() -> AsyncStream<T> {
        let (stream, cont) = AsyncStream<T>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        lock.lock()
        watchers[id] = cont
        if let latest { cont.yield(latest) }
        if source == nil {
            generation += 1
            let values = start(), gen = generation
            source = Task { [weak self] in
                for await v in values { self?.publish(v, gen) }
            }
        }
        lock.unlock()
        cont.onTermination = { [weak self] _ in self?.remove(id) }
        return stream
    }

    private func publish(_ value: T, _ gen: Int) {
        lock.lock()
        guard gen == generation, source != nil else { lock.unlock(); return }
        latest = value
        let targets = Array(watchers.values)
        lock.unlock()
        for c in targets { c.yield(value) }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        watchers[id] = nil
        var ended: Task<Void, Never>?
        if watchers.isEmpty { ended = source; source = nil; latest = nil }
        lock.unlock()
        ended?.cancel()
    }

    /// How many watchers share the observation (the tests read it).
    var watcherCount: Int { lock.lock(); defer { lock.unlock() }; return watchers.count }
}
