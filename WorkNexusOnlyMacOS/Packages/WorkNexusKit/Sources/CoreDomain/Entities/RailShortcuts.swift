/// Not in the Flutter app.
import Foundation

/// The user's choices for the keyboard shortcuts that open the places of the rail. With nothing chosen the places answer
/// to the keys of their position from the top (`ResolveRailShortcuts`: ⌘1 … ⌘0, then ⌥⌘1 … ⌥⌘0); a place can be given
/// other keys, or none.
public struct RailShortcuts: Codable, Equatable, Sendable {
    /// Off: no key opens a place.
    public var enabled = true
    /// The keys chosen for a place, by the place's id.
    public var custom: [String: KeyShortcut] = [:]
    /// The places whose shortcut was removed: they do not take the keys of their position back.
    public var off: Set<String> = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var s = RailShortcuts()
        s.enabled = c.value(.enabled, default: s.enabled)
        s.custom = c.value(.custom, default: s.custom)
        s.off = c.value(.off, default: s.off)
        self = s
    }

    /// Gives `place` these keys (nil: none). A place that answered to them until now is left without a shortcut, so one
    /// combination never opens two places. `places` are the ids of the rail's places, from the top.
    public mutating func assign(_ shortcut: KeyShortcut?, to place: String, places: [String]) {
        guard let shortcut else {
            custom[place] = nil; off.insert(place)
            return
        }
        var whenOn = self
        whenOn.enabled = true
        for (other, keys) in ResolveRailShortcuts()(places: places, settings: whenOn) where other != place && keys == shortcut {
            custom[other] = nil; off.insert(other)
        }
        // A combination chosen for a place that is not on the rail now must not come back with it.
        for (other, keys) in custom where other != place && keys == shortcut { custom[other] = nil; off.insert(other) }
        custom[place] = shortcut; off.remove(place)
    }
}
