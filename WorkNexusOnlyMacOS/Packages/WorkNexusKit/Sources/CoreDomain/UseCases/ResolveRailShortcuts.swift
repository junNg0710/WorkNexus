/// Not in the Flutter app.
import Foundation

/// Which keys open which place of the rail: the keys the user chose for a place, else the keys of its position from the
/// top (`KeyShortcut.byPosition`: ⌘1 … ⌘0, then ⌥⌘1 … ⌥⌘0). A combination chosen for one place is never also another's
/// by position, and a place whose shortcut was removed has none.
public struct ResolveRailShortcuts: Sendable {
    public init() {}

    /// `places` are the ids of the rail's places, from the top. Returns the keys of each place that has some.
    public func callAsFunction(places: [String], settings: RailShortcuts) -> [String: KeyShortcut] {
        guard settings.enabled else { return [:] }
        var out: [String: KeyShortcut] = [:], taken: Set<KeyShortcut> = []
        for place in places {
            guard let chosen = settings.custom[place], !settings.off.contains(place), taken.insert(chosen).inserted else { continue }
            out[place] = chosen
        }
        for (index, place) in places.enumerated() where out[place] == nil && settings.custom[place] == nil && !settings.off.contains(place) {
            guard let byPosition = KeyShortcut.byPosition(index + 1), taken.insert(byPosition).inserted else { continue }
            out[place] = byPosition
        }
        return out
    }
}
