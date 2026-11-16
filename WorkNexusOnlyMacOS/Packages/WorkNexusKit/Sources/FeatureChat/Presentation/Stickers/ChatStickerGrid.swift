/// Ported from: lib/features/chat/presentation/widgets/chat_sticker_grid.dart
import AppKit
import CoreUI
import SwiftUI

/// A sticker set; click sends. With `editable` (the user's own set) the first tile adds images and a sticker is removed from its
/// hover button or the context menu.
struct ChatStickerGrid: View {
    @Environment(\.appTheme) private var theme
    let stickers: [ChatSticker]
    var editable = false
    let store: StickerStore
    let onPick: (ChatSticker) -> Void
    let onError: (String) -> Void

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: theme.spacing.s8), count: 3) }

    var body: some View {
        if editable && stickers.isEmpty {
            VStack(spacing: theme.spacing.s12) {
                StickerTile(help: appString("chatAddSticker", "Add sticker from an image"), action: addFromImages) {
                    Image(systemName: "photo").foregroundStyle(theme.colors.tx2)
                }
                .frame(width: theme.sizes.control36 * 2, height: theme.sizes.control36 * 2)
                Text(appString("chatNoMyStickers", "Add images here, or use “Save as sticker” on an image in a chat."))
                    .font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2).multilineTextAlignment(.center)
            }
            .padding(theme.spacing.s24).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: theme.spacing.s8) {
                    if editable {
                        StickerTile(help: appString("chatAddSticker", "Add sticker from an image"), action: addFromImages) {
                            Image(systemName: "photo").foregroundStyle(theme.colors.tx2)
                        }.aspectRatio(1, contentMode: .fit)
                    }
                    ForEach(stickers) { s in
                        StickerTile(help: s.name, action: { onPick(s) }) { ChatStickerImage(sticker: s).padding(theme.spacing.s4) }
                            .aspectRatio(1, contentMode: .fit)
                            .contextMenu {
                                if editable {
                                    Button(role: .destructive) { remove(s) } label: { Label(appString("chatRemoveSticker", "Remove sticker"), systemImage: "trash") }
                                }
                            }
                    }
                }
                .padding(theme.spacing.s8)
            }
        }
    }

    private func remove(_ s: ChatSticker) {
        Task { if case .failure(let f) = await store.remove(s) { onError(f.message) } }
    }

    /// Lets the user pick images and keeps each as one of their own stickers.
    private func addFromImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    guard let data = try? Data(contentsOf: url) else { continue }
                    if case .failure(let f) = await store.add(bytes: data, name: url.lastPathComponent) { onError(f.message); return }
                }
            }
        }
    }
}

private struct StickerTile<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(hovering ? theme.colors.panel2 : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.help(help)
    }
}
