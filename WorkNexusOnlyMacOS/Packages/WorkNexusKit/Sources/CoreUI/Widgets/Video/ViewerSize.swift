/// Not in the Flutter app (its viewers had a fixed size).
import AppKit
import Observation
import SwiftUI

/// How much of the window a picture or video viewer takes, picked with the viewer's bigger / smaller buttons.
public enum ViewerSizeLevel: Int, CaseIterable, Sendable {
    case small, medium, large, full

    public var share: CGFloat {
        switch self { case .small: 0.6; case .medium: 0.76; case .large: 0.92; case .full: 1 }
    }
}

/// The level the viewers open at: the last one picked, kept on this Mac.
@MainActor @Observable
public final class ViewerSizePreference {
    public static let shared = ViewerSizePreference()
    private static let key = "viewer.sizeLevel"
    private let defaults: UserDefaults

    public private(set) var level: ViewerSizeLevel

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        level = defaults.object(forKey: Self.key).flatMap { ($0 as? Int).flatMap(ViewerSizeLevel.init) } ?? .large
    }

    public var canGrow: Bool { level != .full }
    public var canShrink: Bool { level != .small }
    public func grow() { set(ViewerSizeLevel(rawValue: level.rawValue + 1)) }
    public func shrink() { set(ViewerSizeLevel(rawValue: level.rawValue - 1)) }

    private func set(_ new: ViewerSizeLevel?) {
        guard let new else { return }
        level = new
        defaults.set(new.rawValue, forKey: Self.key)
    }
}

/// A viewer's size for a window (or the space it opens over) at a level.
public enum ViewerSize {
    public static let fallback = CGSize(width: 960, height: 680)
    /// The smallest a viewer gets, unless the window itself is smaller.
    public static let minimum = CGSize(width: 480, height: 360)

    public static func of(window: CGSize?, level: ViewerSizeLevel) -> CGSize {
        guard let w = window, w.width > 0, w.height > 0 else { return fallback }
        return CGSize(width: max(w.width * level.share, min(minimum.width, w.width)),
                      height: max(w.height * level.share, min(minimum.height, w.height)))
    }

    /// Sized from the app's main window now (the fallback where there is none: tests, a hidden window).
    @MainActor public static func current(_ level: ViewerSizeLevel? = nil) -> CGSize {
        let app = NSApp as NSApplication?
        return of(window: (app?.mainWindow ?? app?.keyWindow)?.frame.size, level: level ?? ViewerSizePreference.shared.level)
    }
}

/// The viewer's "smaller" and "larger" buttons.
public struct ViewerSizeButtons: View {
    @Environment(\.appTheme) private var theme
    private let preference: ViewerSizePreference
    public init(preference: ViewerSizePreference = .shared) { self.preference = preference }

    public var body: some View {
        HStack(spacing: theme.spacing.s2) {
            AppIconButton("arrow.down.right.and.arrow.up.left", help: appString("viewerSmaller", "Smaller viewer")) { preference.shrink() }
                .disabled(!preference.canShrink).opacity(preference.canShrink ? 1 : 0.4)
            AppIconButton("arrow.up.left.and.arrow.down.right", help: appString("viewerLarger", "Larger viewer")) { preference.grow() }
                .disabled(!preference.canGrow).opacity(preference.canGrow ? 1 : 0.4)
        }
    }
}
