import Observation
import SwiftUI

/// Whether one view kept mounted by `KeptAlive` is on screen. One object per kept view, put in its environment once and
/// never replaced: a view that reads it (`@KeptAwake`) is drawn again when it changes, and no other.
@MainActor @Observable
public final class KeepAlivePresence {
    /// The view is the one its stack shows.
    public private(set) var isShown: Bool
    /// The kept view this one sits in (a chat inside the chat place), if any.
    @ObservationIgnored private weak var around: KeepAlivePresence?

    public init(shown: Bool, around: KeepAlivePresence? = nil) {
        isShown = shown
        self.around = around
    }

    /// On screen: shown by its stack, and so is every kept view around it.
    public var isAwake: Bool { isShown && (around?.isAwake ?? true) }

    func show(_ shown: Bool) { if shown != isShown { isShown = shown } }
}

/// The presence of each view a `KeptAlive` stack keeps. A class so the stack's body can hand them out without a state
/// change loop (it is only read by the same body that wrote it).
@MainActor
public final class KeepAliveWake {
    /// The view the stack is being drawn with: a view first built now starts as what it is, shown or not.
    private var coming: String?
    private var around: KeepAlivePresence?
    private var presences: [String: KeepAlivePresence] = [:]

    public init() {}

    /// Before the stack's views are built. The presences of views no longer kept are dropped; those already handed out
    /// change in `show(_:)`, after the update that drew the stack — not while it is being drawn.
    public func prepare(shown: String?, keys: [String], around: KeepAlivePresence?) {
        coming = shown
        self.around = around
        if presences.keys.contains(where: { !keys.contains($0) }) { presences = presences.filter { keys.contains($0.key) } }
    }

    /// The presence of the view with `key`, made on first use.
    public func presence(_ key: String) -> KeepAlivePresence {
        if let known = presences[key] { return known }
        let made = KeepAlivePresence(shown: key == coming, around: around)
        presences[key] = made
        return made
    }

    /// `key` is on screen now: it wakes, every other view sleeps.
    public func show(_ key: String?) {
        coming = key
        for (k, presence) in presences { presence.show(k == key) }
    }

    /// Whether the view with `key` is on screen (false for a view never built).
    public func isAwake(_ key: String) -> Bool { presences[key]?.isAwake ?? false }
}

/// Whether the view is on screen — false inside a view `KeptAlive` keeps mounted behind the one shown (a section behind
/// another, a chat behind another): it should not answer shortcuts, start work that is only for a visible view, or run
/// its endless animations (a placeholder's sheen, the typing dots) for nobody. True outside any kept view.
/// Ported from: Flutter's `TickerMode` around each kept-alive section (lib/app/shell/viewport.dart).
@MainActor @propertyWrapper
public struct KeptAwake: DynamicProperty {
    @Environment(KeepAlivePresence.self) private var presence: KeepAlivePresence?

    public init() {}

    public var wrappedValue: Bool { presence?.isAwake ?? true }
}
