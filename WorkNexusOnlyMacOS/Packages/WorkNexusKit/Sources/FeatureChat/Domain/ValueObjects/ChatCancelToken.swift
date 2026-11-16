import Foundation

/// Cooperative cancel for transfers (Dart passes a `Future<void>? cancel`). Thread-safe; handlers fire once, immediately
/// when registered after cancellation.
public final class ChatCancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [UUID: @Sendable () -> Void] = [:]

    public init() {}

    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    public func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let hs = Array(handlers.values)
        handlers.removeAll()
        lock.unlock()
        hs.forEach { $0() }
    }

    /// Runs `handler` on cancel; returns a token to remove it.
    @discardableResult
    public func onCancel(_ handler: @escaping @Sendable () -> Void) -> UUID {
        lock.lock()
        if cancelled { lock.unlock(); handler(); return UUID() }
        let id = UUID()
        handlers[id] = handler
        lock.unlock()
        return id
    }

    public func removeHandler(_ id: UUID) { lock.lock(); handlers[id] = nil; lock.unlock() }
}
