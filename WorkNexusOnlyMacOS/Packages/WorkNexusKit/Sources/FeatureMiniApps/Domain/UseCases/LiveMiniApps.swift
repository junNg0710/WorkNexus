/// Ported from: lib/features/mini_apps/presentation/util/live_mini_apps.dart
/// The mini apps to keep running, least recently shown first: `live` with `current` moved to the end, apps no longer in
/// `existing` dropped, and the oldest closed while more than `max` remain. `current` is never closed.
public func liveMiniApps(live: [String], current: String?, existing: Set<String>, max: Int) -> [String] {
    var next = live.filter { $0 != current && existing.contains($0) }
    if let current, existing.contains(current) { next.append(current) }
    let over = next.count - max
    return over > 0 ? Array(next.dropFirst(over)) : next
}
