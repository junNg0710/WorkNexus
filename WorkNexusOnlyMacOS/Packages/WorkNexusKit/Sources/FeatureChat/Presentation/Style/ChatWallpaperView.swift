/// Ported from: lib/features/chat/presentation/widgets/chat_wallpaper.dart
import AppKit
import CoreUI
import SwiftUI

/// The messages' background, shared by every chat style: the app's plain background, the doodle pattern, a chosen colour
/// (with or without the pattern), or a picked image darkened by `ChatSettings.wallpaperDim` so separators and times stay
/// readable over it. Fills whatever it is placed behind; reads `\.chatSettings` and `\.appTheme`.
public struct ChatWallpaperView: View {
    @Environment(\.chatSettings) private var settings
    @Environment(\.appTheme) private var theme
    public init() {}

    public var body: some View {
        let wallpaper = ChatWallpaperPreview.shared.shown(saved: settings.wallpaper)
        let dark = theme.colors.isDark
        if !chatWallpaperIsPicture(wallpaper) {
            theme.colors.bg
        } else if let chosen = ChatWallpaperColor.parse(wallpaper) {
            // An unreadable colour (a hand-edited setting) falls back to plain.
            if let palette = ChatDoodlePalette.forColor(chosen.color, dark: dark) {
                if chosen.doodles { ChatDoodleCanvas(palette: palette).equatable() } else { palette.base.color }
            } else {
                theme.colors.bg
            }
        } else {
            ChatWallpaperImage(path: wallpaper, dim: settings.wallpaperDim, fallback: theme.colors.bg)
        }
    }
}

/// A picked image as the background, darkened by `dim`.
private struct ChatWallpaperImage: View {
    @Environment(\.appTheme) private var theme
    let path: String; let dim: Double; let fallback: Color
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            fallback
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            }
            if dim > 0 { theme.colors.scrim.opacity(dim) }
        }
        .clipped()
        .task(id: path) {
            // Decoded off the main thread, once per path.
            let p = path
            image = await Task.detached(priority: .utility) { NSImage(contentsOfFile: p) }.value
        }
    }
}
