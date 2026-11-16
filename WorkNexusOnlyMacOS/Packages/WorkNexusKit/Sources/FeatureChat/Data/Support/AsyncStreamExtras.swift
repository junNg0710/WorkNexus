import Foundation

extension AsyncStream {
    /// `map` that stays an `AsyncStream`.
    func mapped<T: Sendable>(_ transform: @escaping @Sendable (Element) -> T) -> AsyncStream<T> where Element: Sendable {
        AsyncStream<T> { cont in
            let task = Task { for await v in self { cont.yield(transform(v)) }; cont.finish() }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}

extension AsyncStream where Element: Equatable {
    /// Drops consecutive equal values (Dart `Stream.distinct`): a table write that changes nothing the consumer shows
    /// does not re-render it.
    func removingDuplicates() -> AsyncStream<Element> {
        AsyncStream { cont in
            let task = Task {
                var last: Element?
                for await v in self {
                    if let last, last == v { continue }
                    last = v
                    cont.yield(v)
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}

/// A value guarded by a lock (small shared state in `@unchecked Sendable` data classes).
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    @discardableResult func with<R>(_ body: (inout Value) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
    var current: Value { lock.lock(); defer { lock.unlock() }; return value }
}

/// Runs async jobs strictly one after another (Dart `ChatSession.enqueue`'s future chain).
final class SerialQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never> = Task {}

    /// Runs `work` after everything queued before; returns when it finished.
    func run(_ work: @escaping @Sendable () async -> Void) async { await submit(work).value }

    /// Queues `work` synchronously — call order is run order — and returns its task.
    @discardableResult
    func submit(_ work: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        lock.lock(); defer { lock.unlock() }
        let previous = tail
        let task = Task { await previous.value; await work() }
        tail = task
        return task
    }
}
