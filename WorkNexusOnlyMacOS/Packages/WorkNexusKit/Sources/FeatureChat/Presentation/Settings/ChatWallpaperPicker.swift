/// Ported from: lib/features/chat/presentation/widgets/chat_wallpaper_picker.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// "Wallpaper" in the chat settings — one background for every chat style: a colour (one tile; `ChatWallpaperColors` under it
/// picks the plain app background, a preset or a free colour, with or without the doodle pattern) or one of the user's images
/// (the + tile adds one, a right click removes it), and how much an image is darkened. Reads `\.chatSettings` and
/// `\.chatServices` (the image store); the host saves what it reports.
public struct ChatWallpaperPicker: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    @Environment(\.chatServices) private var services
    let onSelect: (String) -> Void
    let onDim: (Double) -> Void
    @State private var images: [String] = []
    @State private var failure: String?

    /// - Parameters: `onSelect` gets the new `ChatSettings.wallpaper` value, `onDim` the new `wallpaperDim`.
    public init(onSelect: @escaping (String) -> Void, onDim: @escaping (Double) -> Void) { self.onSelect = onSelect; self.onDim = onDim }

    private var usingImage: Bool { chatWallpaperIsPicture(settings.wallpaper) && ChatWallpaperColor.parse(settings.wallpaper) == nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            Text(shellString("chatWallpaper", "Wallpaper")).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
            FlowLayout(spacing: theme.spacing.s12) {
                ChatWallpaperTile(label: shellString("chatWallpaperColor", "Colour"), selected: !usingImage,
                                  onTap: { if usingImage { onSelect(ChatWallpaperColor.pattern) } }) { ChatWallpaperColourPreview() }
                ForEach(images, id: \.self) { path in
                    ChatWallpaperTile(label: nil, selected: settings.wallpaper == path, onTap: { onSelect(path) }) { ChatWallpaperThumb(path: path) }
                        .contextMenu {
                            Button(role: .destructive) { remove(path) } label: {
                                Label(shellString("chatWallpaperRemove", "Remove wallpaper"), systemImage: "trash")
                            }
                        }
                }
                ChatWallpaperTile(label: shellString("chatWallpaperAdd", "Add an image"), selected: false, onTap: add) {
                    ZStack { theme.colors.panel2; Image(systemName: "photo").foregroundStyle(theme.colors.tx2) }
                }
            }
            if let failure { AppInlineNote(failure, isError: true) }
            if usingImage {
                HStack {
                    Text(shellString("chatWallpaperDim", "Darken")).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                    Slider(value: Binding(get: { min(max(settings.wallpaperDim, 0), 0.8) }, set: onDim), in: 0...0.8).tint(theme.colors.accent)
                }
            } else {
                ChatWallpaperColors(onSelect: onSelect)
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        if case .success(let list)? = await services?.wallpapers?.wallpapers() { images = list }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let store = services?.wallpapers else { return }
        Task {
            guard let bytes = try? Data(contentsOf: url) else { failure = shellString("chatCropAvatarUnreadable", "This picture can't be opened"); return }
            switch await store.add(bytes: bytes, name: url.lastPathComponent) {
            case .success: failure = nil; await reload()
            case .failure(let f): failure = ChatShellLabels.failureText(f)
            }
        }
    }

    private func remove(_ path: String) {
        guard let store = services?.wallpapers else { return }
        Task {
            switch await store.remove(path: path) {
            case .success:
                failure = nil
                if settings.wallpaper == path { onSelect(ChatWallpaperColor.pattern) }
                await reload()
            case .failure(let f): failure = ChatShellLabels.failureText(f)
            }
        }
    }
}

/// A square choice: preview, optional label as its tooltip, accent ring when `selected`.
struct ChatWallpaperTile<Preview: View>: View {
    @Environment(\.appTheme) private var theme
    let label: String?
    let selected: Bool
    let onTap: () -> Void
    @ViewBuilder let preview: Preview

    var body: some View {
        let side = theme.sizes.control36 * 2 + theme.spacing.s4
        let width = selected ? theme.borders.thick : theme.borders.hairline
        // Picked: a thin gap rings the picture inside the accent frame; the picture's corners curve that much tighter.
        let gap = selected ? theme.borders.thick : 0
        let inner = max(0, theme.radii.md - width - gap)
        Button(action: onTap) {
            preview.frame(width: side - 2 * (width + gap), height: side - 2 * (width + gap))
                .clipShape(RoundedRectangle(cornerRadius: inner))
                .padding(gap)
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(selected ? theme.colors.accent : theme.colors.line, lineWidth: width))
                .frame(width: side, height: side)
        }
        .buttonStyle(.plain).help(label ?? "")
    }
}

/// The colour tile's picture: the colour wallpaper on screen (the default pattern while an image is in use).
private struct ChatWallpaperColourPreview: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings

    var body: some View {
        let shown = ChatWallpaperPreview.shared.shown(saved: settings.wallpaper)
        let chosen = chatWallpaperIsPicture(shown) ? (ChatWallpaperColor.parse(shown) ?? ChatWallpaperColor.parse(ChatWallpaperColor.pattern)) : nil
        if let chosen, let palette = ChatDoodlePalette.forColor(chosen.color, dark: theme.colors.isDark) {
            if chosen.doodles { ChatDoodleCanvas(palette: palette, scale: 0.3) } else { palette.base.color }
        } else {
            theme.colors.bg
        }
    }
}

private struct ChatWallpaperThumb: View {
    @Environment(\.appTheme) private var theme
    let path: String
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            theme.colors.skel2
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(theme.colors.tx3) }
        }
        .task(id: path) {
            let p = path
            let decoded = await Task.detached(priority: .utility) { NSImage(contentsOfFile: p) }.value
            image = decoded; failed = decoded == nil
        }
    }
}
