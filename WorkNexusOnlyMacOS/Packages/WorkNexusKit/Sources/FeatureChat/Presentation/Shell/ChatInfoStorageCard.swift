/// Ported from: lib/features/chat/presentation/widgets/chat_info_storage_card.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The info panel's storage card: how much of the chat cache limit this chat's downloads take, split into photos, videos and
/// files; "Manage" opens the storage page.
struct ChatInfoStorageCard: View {
    @Environment(\.appTheme) private var theme
    let repository: ChatRepository
    let accountId: String
    let chatGid: String
    let onManage: (() -> Void)?
    @State private var model: ChatStorageModel

    init(repository: ChatRepository, accountId: String, chatGid: String, onManage: (() -> Void)?) {
        self.repository = repository; self.accountId = accountId; self.chatGid = chatGid; self.onManage = onManage
        _model = State(initialValue: ChatStorageModel(repository: repository))
    }

    var body: some View {
        // Nothing to measure yet (or it failed): no card rather than zeros.
        Group {
            if let all = model.usage {
                let chat = model.usage(accountId: accountId, chatGid: chatGid)
                let kinds = ChatStorageLogic.kinds(imageBytes: chat.imageBytes, videoBytes: chat.videoBytes, fileBytes: chat.fileBytes, theme: theme)
                ChatPanelCard {
                    VStack(alignment: .leading, spacing: theme.spacing.s8) {
                        HStack {
                            Text(shellString("chatStorageThisChat", "Storage")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                            Spacer(minLength: 0)
                            if let onManage { AppButton(shellString("chatStorageManage", "Manage"), kind: .ghost, action: onManage) }
                        }
                        Text(shellString("chatStorageUsed", "{used} of {limit} used",
                                         ["used": ChatShellLabels.fileSize(chat.bytes), "limit": ChatShellLabels.fileSize(all.limitBytes)]))
                            .font(theme.typography.body).foregroundStyle(theme.colors.tx2)
                        ChatStorageBar(total: all.limitBytes, parts: kinds.map { ($0.bytes, $0.color) })
                        ForEach(kinds, id: \.label) { k in
                            HStack(spacing: theme.spacing.s8) {
                                Circle().fill(k.color).frame(width: theme.spacing.s8, height: theme.spacing.s8)
                                Text(k.label).font(theme.typography.body).foregroundStyle(theme.colors.tx)
                                Spacer(minLength: 0)
                                Text(ChatShellLabels.fileSize(k.bytes)).font(theme.typography.body).foregroundStyle(theme.colors.tx2)
                            }
                        }
                    }
                }
                .padding(.bottom, theme.spacing.s8)
            }
        }
        .task(id: chatGid) { await model.load() }
    }
}
