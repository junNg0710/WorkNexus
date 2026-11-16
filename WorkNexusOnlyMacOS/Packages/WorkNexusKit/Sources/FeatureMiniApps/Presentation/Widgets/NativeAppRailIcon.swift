import AppKit
import CoreUI
import SwiftUI

/// New feature, no Dart counterpart. The leading view of a Mac app's rail button: the app's own icon (22pt), a dot while it runs,
/// dimmed when its `.app` is gone. The composition root puts it in a `RailLabeledButton`.
public struct NativeAppRailIcon: View {
    @Environment(\.appTheme) private var theme
    /// The size of the other rail icons (mini apps, accounts).
    static let size: CGFloat = 22
    let icon: NSImage; let running: Bool; let missing: Bool

    public init(icon: NSImage, running: Bool, missing: Bool) { self.icon = icon; self.running = running; self.missing = missing }

    public var body: some View {
        Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            .frame(width: Self.size, height: Self.size)
            .opacity(missing ? 0.35 : 1).saturation(missing ? 0 : 1)
            .overlay(alignment: .bottomTrailing) {
                if running && !missing {
                    Circle().fill(theme.colors.green).frame(width: theme.spacing.s6, height: theme.spacing.s6)
                        .overlay(Circle().stroke(theme.colors.panel, lineWidth: theme.borders.hairline * 2))
                        .offset(x: theme.spacing.s2, y: theme.spacing.s2)
                }
            }
    }
}
