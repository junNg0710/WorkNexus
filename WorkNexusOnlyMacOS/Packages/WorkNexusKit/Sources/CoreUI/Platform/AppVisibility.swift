import AppKit

/// Whether anyone can see the app: polling and animation stop while they cannot (hidden to the tray, minimised, covered).
@MainActor
public enum AppVisibility {
    /// True when a window of the app is visible on screen. Also true where there is no application object at all (a unit
    /// test, a command-line run): nothing there says the work is unseen.
    public static var isOnScreen: Bool {
        guard let app = NSApp as NSApplication? else { return true }
        return app.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) }
    }
}
