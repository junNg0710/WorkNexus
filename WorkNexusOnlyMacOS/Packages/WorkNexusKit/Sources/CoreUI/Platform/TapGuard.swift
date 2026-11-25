/// Ported from: the Flutter app's `TapGuard` (lib/core/utils/tap_guard.dart).
import Foundation

/// Drops repeated taps on one action.
///
/// The first tap runs the action at once; later taps are dropped while that action is still running and for
/// `cooldown` after it completes. This is a leading-edge guard, not a trailing debounce: taps are never merged or
/// delayed, only dropped, so a button never feels laggy. (What it replaces here held a click back until the click
/// behind it had arrived - up to 0.4 s in which nothing answered.)
///
/// One guard per button, or `runShared` with a key when several buttons must not run at the same time (every way into
/// one dialog shares a key, so two of them cannot open it twice). An async action should not return until the work is
/// really over: the lock lasts as long as it does. An action that never returns keeps the lock only until
/// `inFlightTimeout`, so a stuck request cannot disable the button for good.
@MainActor
public final class TapGuard {
    /// Long enough to swallow a double click, short enough not to eat a deliberate second tap.
    public static let defaultCooldown: TimeInterval = 0.3
    /// Safety net for an action that never completes.
    public static let defaultInFlightTimeout: TimeInterval = 10

    public let cooldown: TimeInterval
    public let inFlightTimeout: TimeInterval
    public private(set) var isLocked = false
    private var timer: Task<Void, Never>?
    /// Bumped on every run and release, so a timer or completion of an earlier run can never unlock a later one.
    private var generation = 0

    public init(cooldown: TimeInterval = TapGuard.defaultCooldown, inFlightTimeout: TimeInterval = TapGuard.defaultInFlightTimeout) {
        self.cooldown = cooldown
        self.inFlightTimeout = inFlightTimeout
    }

    /// Runs `action` at once unless a previous one still holds the lock. Returns whether it ran.
    @discardableResult
    public func run(_ action: () -> Void) -> Bool {
        guard !isLocked else { return false }
        let mine = lock()
        action()
        finished(mine)
        return true
    }

    /// `run` for work that goes on after the tap (a request, a page that stays open): locked until it is over.
    @discardableResult
    public func run(_ action: @escaping @MainActor () async -> Void) -> Bool {
        guard !isLocked else { return false }
        let mine = lock()
        after(inFlightTimeout, release: mine)
        Task { @MainActor [weak self] in
            await action()
            self?.finished(mine)
        }
        return true
    }

    /// Unlocks at once, even while the action is still running.
    public func release() {
        generation += 1
        timer?.cancel(); timer = nil
        isLocked = false
    }

    private func lock() -> Int {
        generation += 1
        isLocked = true
        return generation
    }

    private func finished(_ mine: Int) {
        guard mine == generation else { return }
        timer?.cancel(); timer = nil
        if cooldown <= 0 { release() } else { after(cooldown, release: mine) }
    }

    private func after(_ seconds: TimeInterval, release mine: Int) {
        timer?.cancel()
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, mine == self.generation else { return }
            self.release()
        }
    }

    // MARK: shared

    private static var shared: [AnyHashable: TapGuard] = [:]

    /// Like `run`, on a guard shared by every caller that passes the same `key`. The durations only apply when the
    /// guard for `key` is first made.
    @discardableResult
    public static func runShared(_ key: AnyHashable, cooldown: TimeInterval = defaultCooldown,
                                 inFlightTimeout: TimeInterval = defaultInFlightTimeout, _ action: () -> Void) -> Bool {
        guardFor(key, cooldown, inFlightTimeout).run(action)
    }

    @discardableResult
    public static func runShared(_ key: AnyHashable, cooldown: TimeInterval = defaultCooldown,
                                 inFlightTimeout: TimeInterval = defaultInFlightTimeout,
                                 _ action: @escaping @MainActor () async -> Void) -> Bool {
        guardFor(key, cooldown, inFlightTimeout).run(action)
    }

    public static func isSharedLocked(_ key: AnyHashable) -> Bool { shared[key]?.isLocked ?? false }
    public static func releaseShared(_ key: AnyHashable) { shared.removeValue(forKey: key)?.release() }
    public static func releaseAllShared() { shared.values.forEach { $0.release() }; shared = [:] }

    private static func guardFor(_ key: AnyHashable, _ cooldown: TimeInterval, _ inFlightTimeout: TimeInterval) -> TapGuard {
        if let known = shared[key] { return known }
        let made = TapGuard(cooldown: cooldown, inFlightTimeout: inFlightTimeout)
        shared[key] = made
        return made
    }
}
