/// Ported from: lib/features/chat/presentation/widgets/chat_storage_rows.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Per-chat usage, largest first: each row's bar is scaled to the largest chat so they compare at a glance, with its split by
/// kind and a delete button. Files no stored message points to are summed as "Other files".
struct ChatStorageChatList: View {
    @Environment(\.appTheme) private var theme
    let model: ChatStorageModel
    let usage: ChatCacheUsage
    let onClear: (ChatCacheChatUsage, String) -> Void

    var body: some View {
        if usage.chats.isEmpty && usage.otherBytes <= 0 {
            AppInlineNote(shellString("chatStorageEmpty", "Nothing downloaded yet"))
        } else {
            let largest = ([usage.otherBytes] + usage.chats.map(\.bytes)).max() ?? 0
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                Text(shellString("chatStorageByChat", "By chat")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(usage.chats.enumerated()), id: \.offset) { i, chat in
                            if i > 0 { Divider().overlay(theme.colors.line) }
                            let title = model.title(chat)
                            let owner = model.owners[ChatStorageModel.key(chat.accountId, chat.chatGid)]
                            ChatStorageRow(
                                leading: AnyView(owner?.chat.map { ChatAvatarView(chat: $0, title: title, users: owner?.users ?? [:], diameter: theme.sizes.control36) }
                                    ?? ChatAvatarView(name: title, diameter: theme.sizes.control36)),
                                title: title, bytes: chat.bytes, largest: largest,
                                kinds: ChatStorageLogic.kinds(imageBytes: chat.imageBytes, videoBytes: chat.videoBytes, fileBytes: chat.fileBytes, theme: theme),
                                onClear: { onClear(chat, title) })
                        }
                        if usage.otherBytes > 0 {
                            if !usage.chats.isEmpty { Divider().overlay(theme.colors.line) }
                            ChatStorageRow(
                                leading: AnyView(Image(systemName: "folder").foregroundStyle(theme.colors.tx2)
                                    .frame(width: theme.sizes.control36, height: theme.sizes.control36).background(theme.colors.panel2, in: Circle())),
                                title: shellString("chatStorageOther", "Other files"), bytes: usage.otherBytes, largest: largest,
                                kinds: [ChatStorageKind(label: shellString("chatStorageOther", "Other files"), bytes: usage.otherBytes, color: theme.colors.tx3)],
                                onClear: nil)
                        }
                    }
                    .padding(.horizontal, theme.spacing.s12)
                }
                .frame(maxHeight: theme.sizes.dialogLg)
                .fixedSize(horizontal: false, vertical: true)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            }
        }
    }
}

/// One storage row: who, how much, a bar scaled to the largest row split by kinds, the kinds in words under it, and delete.
private struct ChatStorageRow: View {
    @Environment(\.appTheme) private var theme
    let leading: AnyView
    let title: String
    let bytes: Int
    let largest: Int
    let kinds: [ChatStorageKind]
    let onClear: (() -> Void)?

    var body: some View {
        let split = ChatStorageLogic.split(kinds)
        HStack(spacing: theme.spacing.s12) {
            leading
            VStack(alignment: .leading, spacing: theme.spacing.s4) {
                HStack {
                    Text(title).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
                    Spacer(minLength: theme.spacing.s8)
                    Text(ChatShellLabels.fileSize(bytes)).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                }
                ChatStorageBar(total: largest, parts: kinds.map { ($0.bytes, $0.color) }, height: theme.spacing.s4)
                if split.count > 1 || onClear != nil {
                    Text(split.map { "\($0.label) \(ChatShellLabels.fileSize($0.bytes))" }.joined(separator: " · "))
                        .font(theme.typography.caption).foregroundStyle(theme.colors.tx3).lineLimit(1)
                }
            }
            if let onClear { AppIconButton("trash", help: shellString("chatDelete", "Delete"), action: onClear) }
            else { Color.clear.frame(width: theme.sizes.control32, height: theme.sizes.control32) }
        }
        .padding(.vertical, theme.spacing.s12)
    }
}
