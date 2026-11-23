/// Not in the Flutter app.
import Foundation

/// Whether this Mac has a network at all, as macOS says (`NetworkWatcher` keeps it). Background jobs that only ask a
/// server for news (the notification poll, the boards' refresh) wait while it has none, instead of failing every few
/// minutes all night; a request that fails meanwhile is not the app's error. Online until told otherwise.
public enum Connectivity {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var online = true
    }
    private static let state = State()

    public static var isOnline: Bool { state.lock.withLock { state.online } }

    /// Notes a change (once) in the log.
    public static func set(online: Bool) {
        let changed = state.lock.withLock { () -> Bool in
            defer { state.online = online }
            return state.online != online
        }
        if changed { Diagnostics.info("app", online ? "Network: back online" : "Network: offline") }
    }
}
