/// Ported from: lib/features/chat/presentation/widgets/{chat_sticker_pack_bar,chat_sticker_set_buttons}.dart
import CoreUI
import SwiftUI

/// A sticker set's button in the bar.
struct ChatStickerPackCover: Identifiable, Equatable {
    var pack: String
    var title: String?
    var cover: ChatSticker?
    var removable: Bool
    var id: String { pack }
}

/// The row of sticker sets under the grid: the user's own, imported and bundled sets, imports in progress and the "add set" button.
struct ChatStickerPackBar: View {
    @Environment(\.appTheme) private var theme
    let packs: [ChatStickerPackCover]
    let importing: [StickerImportJob]
    let selected: String
    let onSelect: (String) -> Void
    let onImport: () -> Void
    let onRemove: (ChatStickerPackCover) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.s4) {
                    ForEach(Array(packs.enumerated()), id: \.element.id) { i, p in
                        PackButton(pack: p, selected: p.pack == selected) { onSelect(p.pack) }
                            .id(p.pack)
                            .contextMenu {
                                if p.removable {
                                    Button(role: .destructive) { onRemove(p) } label: { Label(appString("stickerPackRemove", "Remove sticker set"), systemImage: "trash") }
                                }
                            }
                        if i == 0 { ForEach(importing) { ImportingChip(job: $0) } }
                    }
                    ComposerToolButton(systemImage: "plus", help: appString("stickerImportTitle", "Add a Telegram sticker set"), action: onImport)
                }
                .padding(.horizontal, theme.spacing.s8)
            }
            .onChange(of: selected) { _, new in withAnimation(.easeOut(duration: theme.motion.base)) { proxy.scrollTo(new, anchor: .center) } }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
        .frame(height: theme.sizes.control36 + theme.spacing.s8)
    }
}

private struct PackButton: View {
    @Environment(\.appTheme) private var theme
    let pack: ChatStickerPackCover
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let cover = pack.cover { ChatStickerImage(sticker: cover).padding(theme.spacing.s4) }
                else { Image(systemName: "heart").foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2) }
            }
            .frame(width: theme.sizes.control36, height: theme.sizes.control36)
            .background(selected ? theme.colors.sel : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pack.cover == nil ? appString("chatMyStickers", "My stickers") : (pack.title ?? pack.pack))
    }
}

/// A set being imported: a small spinner with its progress.
private struct ImportingChip: View {
    @Environment(\.appTheme) private var theme
    let job: StickerImportJob

    var body: some View {
        ZStack {
            Circle().stroke(theme.colors.line, lineWidth: theme.borders.thick)
            Circle().trim(from: 0, to: job.total > 0 ? Double(job.done) / Double(job.total) : 0.05)
                .stroke(theme.colors.accent, style: StrokeStyle(lineWidth: theme.borders.thick, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .frame(width: theme.sizes.icon20, height: theme.sizes.icon20)
        .frame(width: theme.sizes.control36, height: theme.sizes.control36)
        .help(appString("stickerImportRunning", "Adding “{title}” · {done}/{total}")
            .replacingOccurrences(of: "{title}", with: job.title).replacingOccurrences(of: "{done}", with: "\(job.done)")
            .replacingOccurrences(of: "{total}", with: "\(job.total)"))
    }
}
