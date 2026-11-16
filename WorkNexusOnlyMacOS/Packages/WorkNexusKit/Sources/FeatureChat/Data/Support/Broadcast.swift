import Foundation

/// Multi-subscriber event hub (Dart `StreamController.broadcast`). `stream()` may be called before events start flowing;
/// late subscribers see only later events unless `replay` is set (then they first get the latest value).
final class Broadcast<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var subs: [UUID: AsyncStream<T>.Continuation] = [:]
    private var latest: T?
    private var finished = false
    private let replay: Bool

    init(replay: Bool = false) { self.replay = replay }

    func stream() -> AsyncStream<T> {
        AsyncStream(bufferingPolicy: .unbounded) { cont in
            let id = UUID()
            lock.lock()
            if finished { lock.unlock(); cont.finish(); return }
            subs[id] = cont
            let last = replay ? latest : nil
            lock.unlock()
            if let last { cont.yield(last) }
            cont.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.subs[id] = nil; self.lock.unlock()
            }
        }
    }

    func send(_ value: T) {
        lock.lock()
        latest = value
        let targets = Array(subs.values)
        lock.unlock()
        targets.forEach { $0.yield(value) }
    }

    func finish() {
        lock.lock()
        finished = true
        let targets = Array(subs.values)
        subs.removeAll()
        lock.unlock()
        targets.forEach { $0.finish() }
    }
}
