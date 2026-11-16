import Foundation

public extension KeyedDecodingContainer {
    /// Missing or malformed keys fall back to `fallback` (mirrors freezed `@Default`).
    func value<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }
}

/// Cooperative cancel flag (lib/core/util/cancel_signal.dart).
public final class CancelSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    public func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}
