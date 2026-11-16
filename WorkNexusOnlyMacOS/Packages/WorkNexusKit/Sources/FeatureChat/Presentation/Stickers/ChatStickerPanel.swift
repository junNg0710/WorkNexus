/// Ported from: lib/features/chat/presentation/widgets/chat_sticker_panel.dart + providers/sticker_providers.dart
import CoreUI
import SwiftUI

/// Every sticker set: the grid of the chosen set over the bar of sets. A click sends (`onPick`). The bar starts with the
/// stickers sent lately (not in the Flutter app), once there are any.
struct ChatStickerPanel: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let stickers: [ChatSticker]
    let store: StickerStore
    let onPick: (ChatSticker) -> Void
    let onError: (String) -> Void
    @State private var pack: String?
    @State private var importOpen = false
    @State private var removing: ChatStickerPackCover?
    private var jobs: StickerImportJobs { .shared }

    private struct Sets {
        var mine: [ChatSticker] = []
        var imported: [(String, [ChatSticker])] = []
        var bundled: [(String, [ChatSticker])] = []
        var all: [String: [ChatSticker]] = [:]
    }

    private var sets: Sets {
        var s = Sets()
        for st in stickers {
            if st.custom && st.pack.isEmpty { s.mine.append(st); continue }
            if st.custom {
                if let i = s.imported.firstIndex(where: { $0.0 == st.pack }) { s.imported[i].1.append(st) } else { s.imported.append((st.pack, [st])) }
            } else {
                if let i = s.bundled.firstIndex(where: { $0.0 == st.pack }) { s.bundled[i].1.append(st) } else { s.bundled.append((st.pack, [st])) }
            }
        }
        for (k, v) in s.imported + s.bundled { s.all[k] = v }
        return s
    }

    var body: some View {
        let sets = sets
        let recents = store.recents(in: stickers)
        let recentPack = StickerStore.recentPack
        let known: (String) -> Bool = { $0.isEmpty || sets.all[$0] != nil || ($0 == recentPack && !recents.isEmpty) }
        let last = store.lastPack
        let current = (pack.flatMap { known($0) ? $0 : nil }) ?? (last.flatMap { known($0) ? $0 : nil })
            ?? (sets.mine.isEmpty && !sets.all.isEmpty ? (sets.imported + sets.bundled).first!.0 : "")
        let onRecent = current == recentPack
        VStack(spacing: 0) {
            ChatStickerGrid(stickers: onRecent ? recents : current.isEmpty ? sets.mine : sets.all[current] ?? [], editable: current.isEmpty, store: store,
                            // Sent from the recent ones, the bar stays on them; from a set, that set is the one to reopen on.
                            onPick: { if !onRecent { store.remember($0.pack) }; store.noteSent($0); onPick($0) }, onError: onError)
                // The recent grid keeps its identity while its order changes (the sticker just sent moves to the front).
                .id(current)
            Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline)
            ChatStickerPackBar(
                packs: (recents.isEmpty ? [] : [ChatStickerPackCover(pack: recentPack, title: appString("chatRecentStickers", "Recently sent"),
                                                                     cover: nil, removable: false, symbol: "clock.arrow.circlepath")])
                    + [ChatStickerPackCover(pack: "", title: nil, cover: nil, removable: false)]
                    + sets.imported.map { ChatStickerPackCover(pack: $0.0, title: $0.1.first?.packTitle, cover: $0.1.first, removable: true) }
                    + sets.bundled.map { ChatStickerPackCover(pack: $0.0, title: nil, cover: $0.1.first, removable: false) },
                importing: jobs.running, selected: current,
                onSelect: { pack = $0; store.remember($0) }, onImport: { importOpen = true }, onRemove: { removing = $0 })
        }
        .sheet(isPresented: $importOpen) { ImportStickerPackSheet() }
        .confirmationDialog(
            appString("stickerPackRemoveTitle", "Remove “{title}”?").replacingOccurrences(of: "{title}", with: removing?.title ?? removing?.pack ?? ""),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing
        ) { p in
            Button(appString("stickerPackRemove", "Remove sticker set"), role: .destructive) {
                Task {
                    switch await store.removePack(p.pack) {
                    case .success: if pack == p.pack { pack = nil }
                    case .failure(let f): onError(f.message)
                    }
                }
            }
        } message: { _ in Text(appString("stickerPackRemoveMessage", "Its stickers will be removed from this device.")) }
    }
}
