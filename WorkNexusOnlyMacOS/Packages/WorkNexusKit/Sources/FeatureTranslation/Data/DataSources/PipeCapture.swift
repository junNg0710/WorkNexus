import Foundation

/// Ported from: lib/features/translation/data/opencode_translation_service.dart (`_Capture`)
/// Reads a CLI's output pipe as it arrives, so a run can stop waiting for the pipe to close and still keep what has been read.
final class PipeCapture: @unchecked Sendable {
    private final class Waiter: @unchecked Sendable {
        private let lock = NSLock(); private var cont: CheckedContinuation<Void, Never>?
        init(_ cont: CheckedContinuation<Void, Never>) { self.cont = cont }
        func fire() { lock.lock(); let c = cont; cont = nil; lock.unlock(); c?.resume() }
    }

    private let lock = NSLock()
    private var buffer = Data()
    private var closed = false
    private var waiters: [Waiter] = []
    private let handle: FileHandle

    init(_ pipe: Pipe) {
        handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; self?.close() } else { self?.append(d) }
        }
    }

    private func snapshot() -> String { lock.lock(); defer { lock.unlock() }; return String(decoding: buffer, as: UTF8.self) }

    private func append(_ d: Data) { lock.lock(); buffer.append(d); lock.unlock() }

    private func close() {
        lock.lock(); closed = true; let w = waiters; waiters = []; lock.unlock()
        w.forEach { $0.fire() }
    }

    /// What the pipe carried. Waits for it to close, or, given `within`, at most that long, after which it stops reading.
    func text(within: TimeInterval? = nil) async -> String {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if closed { lock.unlock(); c.resume(); return }
            let w = Waiter(c); waiters.append(w); lock.unlock()
            if let within { DispatchQueue.global().asyncAfter(deadline: .now() + within) { w.fire() } }
        }
        handle.readabilityHandler = nil
        return snapshot()
    }
}
