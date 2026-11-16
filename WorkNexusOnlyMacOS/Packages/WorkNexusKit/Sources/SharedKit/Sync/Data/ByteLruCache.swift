import Foundation

/// Ported from: lib/core/cache/byte_lru_cache.dart
/// Byte-bounded LRU of downloaded images (ticket images fetched with the account's auth).
public final class ByteLruCache: @unchecked Sendable {
    private let lock = NSLock()
    private var order: [String] = []
    private var values: [String: Data] = [:]
    private var total = 0
    public let maxBytes: Int

    public init(maxBytes: Int = 64 * 1024 * 1024) { self.maxBytes = maxBytes }

    public func get(_ key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let v = values[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return v
    }

    public func put(_ key: String, _ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if let old = values[key] { total -= old.count; order.removeAll { $0 == key } }
        guard data.count <= maxBytes else { return }
        values[key] = data; total += data.count; order.append(key)
        while total > maxBytes, let oldest = order.first {
            order.removeFirst()
            if let v = values.removeValue(forKey: oldest) { total -= v.count }
        }
    }

    public var byteCount: Int { lock.lock(); defer { lock.unlock() }; return total }
    public func clear() { lock.lock(); order = []; values = [:]; total = 0; lock.unlock() }
}
