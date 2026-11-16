import CoreDomain
import Foundation
import Observation

/// The settings as the `@Sendable` closures of features read them (mini-app limits, chat notification preferences,
/// auto-download…). Kept in step with the DB by `CompositionRoot`'s settings watcher.
final class LiveSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var current = AppSettings()
    var value: AppSettings { lock.lock(); defer { lock.unlock() }; return current }
    func set(_ s: AppSettings) { lock.lock(); current = s; lock.unlock() }
}

/// Process-memory credential store for demo / UI-test runs (`WN_DEMO=1`): the user's keychain is never touched.
actor MemoryCredentialStore: CredentialStore {
    private var items: [String: String] = [:]
    func read(_ key: String) async -> String? { items[key] }
    func write(_ key: String, value: String) async -> Outcome<Void> { items[key] = value; return .success(()) }
    func delete(_ key: String) async -> Outcome<Void> { items[key] = nil; return .success(()) }
}

/// The first value of an account stream (the accounts as they are now).
func currentAccounts(_ repo: WorkspaceRepository) async -> [Account] {
    var it = repo.watchAccounts().makeAsyncIterator()
    return await it.next() ?? []
}

/// Runs `body` on the main thread whether or not the caller is on it.
func onMain<T: Sendable>(_ body: @MainActor () -> T) -> T {
    if Thread.isMainThread { return MainActor.assumeIsolated { body() } }
    return DispatchQueue.main.sync { MainActor.assumeIsolated { body() } }
}

/// Calls `onChange` with the new value every time an `@Observable` value read by `read` changes (not for the first value).
@MainActor
func observeChanges<T>(_ read: @escaping @MainActor () -> T, _ onChange: @escaping @MainActor (T) -> Void) {
    withObservationTracking { _ = read() } onChange: {
        Task { @MainActor in onChange(read()); observeChanges(read, onChange) }
    }
}
