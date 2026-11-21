/// Not in the Flutter app.
import AppKit

/// The app the user was in before WorkNexus: the one a click on the floating pet can put back in front, leaving WorkNexus
/// under it where it was, rather than hiding WorkNexus.
@MainActor
public final class LastOtherApp {
    public static let shared = LastOtherApp()

    private var app: NSRunningApplication?
    private var observer: NSObjectProtocol?

    /// Starts following which app is in front, once.
    public func start() {
        guard observer == nil else { return }
        remember(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.remember(app) }
        }
    }

    /// There is such an app, still running.
    public var isAvailable: Bool { app.map { !$0.isTerminated } ?? false }

    /// Brings that app back in front; false when there is none (it quit since).
    public func activate() -> Bool {
        guard let app, !app.isTerminated else { return false }
        NSApp.yieldActivation(to: app)
        return app.activate()
    }

    private func remember(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        self.app = app
    }
}
