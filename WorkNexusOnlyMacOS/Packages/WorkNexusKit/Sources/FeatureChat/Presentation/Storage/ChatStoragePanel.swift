/// Ported from: lib/features/chat/presentation/widgets/chat_storage_panel.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Disk space of downloaded chat files: how much is used against the limit, the limit itself, per-chat usage with delete,
/// and "clear all". The chat part of the app's storage page; reads `\.chatServices`.
public struct ChatStoragePanel: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let limitMb: Int
    let onLimitChange: (Int) -> Void
    let onCleared: () -> Void

    /// - Parameters: `limitMb` is the saved cache limit; `onLimitChange` saves a new one; `onCleared` runs after files were
    ///   deleted (the host may refresh whatever shows them).
    public init(limitMb: Int, onLimitChange: @escaping (Int) -> Void, onCleared: @escaping () -> Void = {}) {
        self.limitMb = limitMb; self.onLimitChange = onLimitChange; self.onCleared = onCleared
    }

    public var body: some View {
        if let chat = services?.chat { ChatStoragePanelBody(repository: chat, limitMb: limitMb, onLimitChange: onLimitChange, onCleared: onCleared) }
    }
}

private struct PendingClear: Identifiable {
    var accountId: String?
    var chatGid: String?
    var question: String
    var id: String { "\(accountId ?? "")/\(chatGid ?? "")" }
}

private struct ChatStoragePanelBody: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var model: ChatStorageModel
    @State private var pending: PendingClear?
    @State private var failure: String?
    let limitMb: Int
    let onLimitChange: (Int) -> Void
    let onCleared: () -> Void

    init(repository: ChatRepository, limitMb: Int, onLimitChange: @escaping (Int) -> Void, onCleared: @escaping () -> Void) {
        _model = State(initialValue: ChatStorageModel(repository: repository))
        self.limitMb = limitMb; self.onLimitChange = onLimitChange; self.onCleared = onCleared
    }

    var body: some View {
        let limits = ChatStorageLogic.limitsMb.contains(limitMb) ? ChatStorageLogic.limitsMb : [limitMb] + ChatStorageLogic.limitsMb
        VStack(alignment: .leading, spacing: theme.spacing.s16) {
            if let usage = model.usage { ChatStorageMeter(usage: usage, limitBytes: limitMb * 1024 * 1024) }
            else if model.failed { AppInlineNote(shellString("chatAttachmentFailed", "Couldn't load the attachment"), isError: true) }
            else { AppInlineSpinner() }
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                HStack {
                    Text(shellString("chatStorageLimit", "Size limit")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                    Spacer()
                    AppDropdown(value: limitMb, values: limits, labelOf: ChatStorageLogic.limitLabel) { mb in
                        onLimitChange(mb)
                        // Lowering the limit trims; show the new usage after.
                        Task { try? await Task.sleep(for: .milliseconds(500)); await model.load() }
                    }
                    .frame(width: theme.sizes.dialogSm / 2)
                }
                Text(shellString("chatStorageLimitHint", "When the limit is reached, the files viewed longest ago are removed first."))
                    .font(theme.typography.caption).foregroundStyle(theme.colors.tx2)
            }
            if let usage = model.usage {
                ChatStorageChatList(model: model, usage: usage) { chat, title in
                    pending = PendingClear(accountId: chat.accountId, chatGid: chat.chatGid,
                                           question: shellString("chatStorageClearChatConfirm", "Delete the downloaded files of {chat}? Messages are kept; files download again when opened.", ["chat": title]))
                }
            }
            if let failure { AppInlineNote(failure, isError: true) }
            AppButton(shellString("chatStorageClearAll", "Clear all"), kind: .danger) {
                pending = PendingClear(question: shellString("chatStorageClearAllConfirm", "Delete all downloaded chat files? Messages are kept; files download again when opened."))
            }
        }
        .task { await model.load() }
        .appDialog(item: $pending) { p in
            AppConfirmDialog(title: shellString("chatStorageClearTitle", "Delete downloaded files?"), message: p.question,
                             confirmLabel: shellString("chatDelete", "Delete"), destructive: true,
                             onConfirm: { pending = nil; Task { await clear(p) } }, onCancel: { pending = nil })
        }
    }

    private func clear(_ p: PendingClear) async {
        failure = await model.clear(accountId: p.accountId, chatGid: p.chatGid)
        if failure == nil { toasts?.show(shellString("chatStorageCleared", "Cleared")); onCleared() }
    }
}
