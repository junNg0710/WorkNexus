import AppKit
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/attachment_viewer_dialog.dart (the dialog's size rule) +
/// lib/core/platform/desktop_window_service.dart (full screen)
/// A viewer that follows its window instead of a fixed size: 80% wide / 85% tall of the space it is given, between
/// 360x320 and 960x720 (as Flutter's dialog did); `expanded` fills the whole space. Draw it inside a dialog or overlay.
public struct AdaptiveViewerFrame<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let expanded: Bool
    let content: Content
    public init(expanded: Bool, @ViewBuilder content: () -> Content) { self.expanded = expanded; self.content = content() }

    /// The viewer's size in a space of `container`: all of it when expanded, else the share picked with the viewer's bigger /
    /// smaller buttons (`ViewerSizeButtons`).
    public static func size(in container: CGSize, expanded: Bool, level: ViewerSizeLevel = .large) -> CGSize {
        expanded ? container : ViewerSize.of(window: container, level: level)
    }

    public var body: some View {
        GeometryReader { geo in
            let size = Self.size(in: geo.size, expanded: expanded, level: ViewerSizePreference.shared.level)
            content.frame(width: size.width, height: size.height)
                .background(theme.colors.card, in: RoundedRectangle(cornerRadius: expanded ? 0 : theme.radii.lg))
                .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : theme.radii.lg))
                .overlay(RoundedRectangle(cornerRadius: expanded ? 0 : theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: theme.motion.base), value: size)
        }
    }
}

/// Puts the key window into / out of full screen (a video's "expand").
@MainActor
public enum AppWindowFullScreen {
    public static var isFullScreen: Bool { NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false }
    public static func toggle() { NSApp.keyWindow?.toggleFullScreen(nil) }
    public static func exit() { if isFullScreen { toggle() } }
}
