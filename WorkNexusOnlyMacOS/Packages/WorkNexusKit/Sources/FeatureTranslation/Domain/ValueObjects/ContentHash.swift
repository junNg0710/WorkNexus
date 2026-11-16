/// Ported from: lib/core/util/content_hash.dart
/// Stable, deterministic content hash that keys translation caches and detects when a ticket's source text changed
/// since it was translated. Not cryptographic. Hashes UTF-16 code units, exactly like Dart's `codeUnitAt`, so cached
/// hashes from the Flutter build keep matching.
public func contentHash(_ title: String, _ body: String) -> String {
    String(intHash("\(title) \(body)"), radix: 16)
}

/// Stable non-negative 31-bit hash of a string (h*31+c).
public func intHash(_ s: String) -> Int {
    var h = 0
    for unit in s.utf16 { h = ((h &* 31) &+ Int(unit)) & 0x7fff_ffff }
    return h
}
