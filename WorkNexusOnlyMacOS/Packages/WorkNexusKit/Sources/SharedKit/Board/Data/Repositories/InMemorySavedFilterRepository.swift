import CoreDomain
import Foundation

/// In-memory `SavedFilterRepository` (tests, previews, and the default until the composition root injects a
/// database-backed one over the core `savedFilters` table using `SavedFilterMapper`). Newest preset first.
public final class InMemorySavedFilterRepository: SavedFilterRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SavedFilter]
    private var listeners: [UUID: AsyncStream<[SavedFilter]>.Continuation] = [:]

    public init(_ initial: [SavedFilter] = []) { items = initial }

    private func sorted() -> [SavedFilter] { items.sorted { $0.createdAt > $1.createdAt } }

    public func watchSavedFilters() -> AsyncStream<[SavedFilter]> {
        AsyncStream { cont in
            let id = UUID()
            lock.lock(); listeners[id] = cont; let cur = sorted(); lock.unlock()
            cont.yield(cur)
            cont.onTermination = { [weak self] _ in self?.lock.lock(); self?.listeners[id] = nil; self?.lock.unlock() }
        }
    }

    public func upsert(_ filter: SavedFilter) async -> Outcome<Void> {
        publish { if let i = items.firstIndex(where: { $0.id == filter.id }) { items[i] = filter } else { items.append(filter) } }
        return .success(())
    }

    public func delete(id: String) async -> Outcome<Void> {
        publish { items.removeAll { $0.id == id } }
        return .success(())
    }

    private func publish(_ change: () -> Void) {
        lock.lock(); change(); let cur = sorted(); let ls = Array(listeners.values); lock.unlock()
        ls.forEach { $0.yield(cur) }
    }
}

/// The saved-filter repository every board shares (Flutter: one `savedFilterRepository` in the service locator). The
/// composition root installs the database-backed one at start-up (`SavedFilterStorage.install`); until then — tests, previews —
/// boards get an in-memory one. `BoardController` takes it as the default of its `savedFilters:` parameter, so every tool's
/// boards (ZenTao, GitLab, GitHub) share the same presets without being told.
public enum SavedFilterStorage {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var installed: SavedFilterRepository?
    nonisolated(unsafe) private static var fallback: SavedFilterRepository?

    /// The repository boards use.
    public static var shared: SavedFilterRepository {
        lock.withLock {
            if let installed { return installed }
            if let fallback { return fallback }
            let memory = InMemorySavedFilterRepository()
            fallback = memory
            return memory
        }
    }

    /// Makes `repository` the one boards created from now on use.
    public static func install(_ repository: SavedFilterRepository) { lock.withLock { installed = repository } }
}
