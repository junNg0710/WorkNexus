import AppKit

/// Ported from: lib/core/platform/app_icon_badge.dart (macOS branch)
/// A count on the app's Dock icon. Cosmetic: never throws.
@MainActor
public protocol DockBadging: AnyObject {
    /// Shows `count` on the icon, or clears it at 0 or below.
    func show(_ count: Int)
}

@MainActor
public final class DockBadge: DockBadging {
    public init() {}

    public func show(_ count: Int) {
        NSApp?.dockTile.badgeLabel = Self.label(count)
    }

    /// Empty clears the badge; above 99 reads `99+`.
    public nonisolated static func label(_ count: Int, max: Int = 99) -> String {
        if count <= 0 { return "" }
        return count > max ? "\(max)+" : "\(count)"
    }
}
