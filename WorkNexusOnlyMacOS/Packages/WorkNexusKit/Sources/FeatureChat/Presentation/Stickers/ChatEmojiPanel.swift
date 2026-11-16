/// Ported from: lib/features/chat/presentation/widgets/{chat_emoji_panel,chat_emoji_picker}.dart
import CoreUI
import SwiftUI

/// The emoji offered: those the server keeps (sent as Emojione shortnames), in the picker's order. Older symbols get the emoji
/// variation selector, or macOS draws them as plain text glyphs.
enum ChatEmojiList {
    static let all: [String] = ChatEmojiTables.basic.compactMap { entry in
        guard let u = Unicode.Scalar(entry.codePoint) else { return nil }
        return entry.codePoint > 0xFFFF ? String(Character(u)) : String(Character(u)) + "\u{FE0F}"
    }
}

/// The emoji and sticker picker as a popup over the composer. `onInsert` types an emoji into the input; `onSent` is called as a
/// sticker is sent (closes the popup); `onExpand`, when given, adds a button that moves it beside the chat instead.
public struct ChatEmojiPanel: View {
    @Environment(\.appTheme) private var theme
    let state: ChatThreadState
    let onInsert: (String) -> Void
    let onSent: () -> Void
    var onExpand: (() -> Void)?
    var threadRootId: Int?

    init(state: ChatThreadState, onInsert: @escaping (String) -> Void, onSent: @escaping () -> Void, onExpand: (() -> Void)? = nil, threadRootId: Int? = nil) {
        self.state = state; self.onInsert = onInsert; self.onSent = onSent; self.onExpand = onExpand; self.threadRootId = threadRootId
    }

    public var body: some View {
        ChatEmojiTabs(state: state, threadRootId: threadRootId, onInsert: onInsert, onSent: onSent) {
            if let onExpand { AppIconButton("arrow.up.left.and.arrow.down.right", help: appString("chatEmojiExpand", "Expand"), action: onExpand) }
        }
        .background(theme.colors.card)
    }
}

/// Two tabs: stickers (every set, switched from the bar at the bottom) and emoji to type — an emoji sent on its own shows large.
/// A sticker answers the composer's reply draft (which is then cleared), else `threadRootId` in a thread — like a typed message.
struct ChatEmojiTabs<Action: View>: View {
    private enum Tab { case stickers, emoji }
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.chatSettings) private var settings
    let state: ChatThreadState
    var threadRootId: Int?
    let onInsert: (String) -> Void
    let onSent: () -> Void
    @ViewBuilder let action: Action
    @State private var tab = Tab.stickers
    @State private var store: StickerStore?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s4) {
                TabButton(title: appString("chatStickersTab", "Stickers"), selected: tab == .stickers) { tab = .stickers }
                TabButton(title: appString("chatEmoji", "Emoji"), selected: tab == .emoji) { tab = .emoji }
                Spacer(minLength: 0)
                action
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
            Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline)
            if let error {
                Text(error).font(theme.typography.meta).foregroundStyle(theme.colors.red).padding(theme.spacing.s6)
            }
            switch tab {
            case .emoji: EmojiGrid(onPick: onInsert)
            case .stickers: stickers
            }
        }
        .task { await load() }
        .task(id: StickerImportJobs.shared.importedTick) { if store != nil { await store?.reload() } }
    }

    @ViewBuilder private var stickers: some View {
        if let store {
            switch store.phase {
            case .loading: ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let m): Text(m).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let all): ChatStickerPanel(stickers: all, store: store, onPick: send, onError: { error = $0 })
            }
        } else {
            Text(appString("chatAttachmentFailed", "Couldn't load the attachment")).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        guard store == nil, let repo = services?.stickers else { return }
        let s = StickerStore(repo)
        store = s
        await s.reload()
    }

    private func send(_ sticker: ChatSticker) {
        guard let services else { return }
        let sender = ChatMessageSender(state: state, services: services, settings: settings, threadRootId: threadRootId)
        onSent()
        Task { if case .failure(let f) = await sender.sticker(sticker) { error = f.message } }
    }
}

private struct TabButton: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(theme.typography.label).foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
                .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s6)
                .background(selected ? theme.colors.sel : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
        }
        .buttonStyle(.plain)
    }
}

/// The emoji to type, 8 across.
private struct EmojiGrid: View {
    @Environment(\.appTheme) private var theme
    let onPick: (String) -> Void
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 0), count: 8) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(ChatEmojiList.all, id: \.self) { e in EmojiCell(emoji: e) { onPick(e) } }
            }
            .padding(theme.spacing.s8)
        }
    }
}

private struct EmojiCell: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let emoji: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(emoji).font(.system(size: 22)).frame(maxWidth: .infinity).frame(height: theme.sizes.control36 + theme.spacing.s4)
                .background(hovering ? theme.colors.panel2 : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}
