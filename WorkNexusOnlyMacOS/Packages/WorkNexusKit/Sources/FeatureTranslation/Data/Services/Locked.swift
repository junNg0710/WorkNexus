import Foundation

/// Small mutex-guarded box for state shared between async tasks (scoped locking only, so it is safe across `await`).
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
}
