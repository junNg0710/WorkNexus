/// Not in the Flutter app (its viewers had a fixed size).
import AppKit

/// How big a picture or video viewer opens: most of the window it opens over, so a large screen shows a large picture.
enum ChatViewerSize {
    static let fallback = CGSize(width: 960, height: 680)
    static let minimum = CGSize(width: 720, height: 520)
    static let maximum = CGSize(width: 2200, height: 1500)
    /// The share of the window the viewer takes.
    static let share: CGFloat = 0.92

    static func of(window: CGSize?) -> CGSize {
        guard let w = window, w.width > 0, w.height > 0 else { return fallback }
        return CGSize(width: min(max(w.width * share, minimum.width), maximum.width),
                      height: min(max(w.height * share, minimum.height), maximum.height))
    }

    /// Sized from the app's main window now (the fallback where there is none: tests, a hidden window).
    @MainActor static var current: CGSize {
        let app = NSApp as NSApplication?
        return of(window: (app?.mainWindow ?? app?.keyWindow)?.frame.size)
    }
}
