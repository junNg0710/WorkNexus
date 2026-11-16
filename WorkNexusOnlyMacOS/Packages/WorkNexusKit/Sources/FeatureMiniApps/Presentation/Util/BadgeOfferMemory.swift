import Foundation

/// New feature, no Dart counterpart. What the app remembers about asking for the Dock badges: whether the user turned
/// the offer down, and whether badges were ever readable (so losing the access again can be told apart from never having had it).
@MainActor
public protocol BadgeOfferMemory: AnyObject {
    var declined: Bool { get set }
    var wasAllowed: Bool { get set }
}

/// Forgets with the process (tests, previews).
@MainActor
public final class InMemoryBadgeOfferMemory: BadgeOfferMemory {
    public var declined = false
    public var wasAllowed = false
    public init() {}
}

@MainActor
public final class UserDefaultsBadgeOfferMemory: BadgeOfferMemory {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var declined: Bool {
        get { defaults.bool(forKey: "nativeApps.badgeOffer.declined") }
        set { defaults.set(newValue, forKey: "nativeApps.badgeOffer.declined") }
    }
    public var wasAllowed: Bool {
        get { defaults.bool(forKey: "nativeApps.badges.wasAllowed") }
        set { defaults.set(newValue, forKey: "nativeApps.badges.wasAllowed") }
    }
}

/// Why the app offers to turn the Dock badges on.
public enum BadgeOffer: Equatable, Sendable {
    /// Never asked: there are Mac apps on the rail and macOS has not been told to let the app read the Dock.
    case first
    /// It worked before and stopped: macOS no longer trusts the app (an unsigned build is a new app after every update).
    case lost
}
