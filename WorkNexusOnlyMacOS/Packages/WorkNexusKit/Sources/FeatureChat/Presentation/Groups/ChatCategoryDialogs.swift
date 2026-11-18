import CoreDomain
import CoreUI
import SwiftUI

/// Files a chat under a category: an existing one picked from chips, or a new one typed; one already filed can also be
/// taken out.
/// Ported from: lib/features/chat/presentation/widgets/chat_category_actions.dart (`showChatCategoryPicker`)
struct ChatCategoryPickerDialog: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let chat: ChatConversation
    let onClose: () -> Void

    var body: some View {
        let existing = model.categories.map(\.name)
        ChatNameDialog(title: shellString("chatCategorizeTitle", "Categorize chat"), initial: chat.category,
                       hint: shellString("chatCategoryName", "Category name, e.g. Projects"),
                       onSave: { await model.setCategory(chat, $0) }, onClose: onClose) { name in
            if !existing.isEmpty {
                FlowLayout(spacing: theme.spacing.s6) {
                    ForEach(existing, id: \.self) { c in
                        ChatTabChip(label: c, selected: name.wrappedValue.trimmingCharacters(in: .whitespaces) == c, icon: "folder") {
                            name.wrappedValue = c
                        }
                    }
                }
                .padding(.top, theme.spacing.s16)
            }
            if !chat.category.isEmpty {
                AppButton(shellString("chatRemoveCategory", "Remove from category"), systemImage: "folder.badge.minus", kind: .ghost) {
                    Task { if await model.setCategory(chat, "") { onClose() } }
                }
                .padding(.top, theme.spacing.s16)
            }
        }
    }
}

/// The user's category tags, each to rename or delete. New tags come from filing a chat (its right-click menu), as a tag
/// is only a name on chats.
/// Ported from: lib/features/chat/presentation/widgets/chat_category_manager_dialog.dart
struct ChatCategoryManagerDialog: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel

    var body: some View {
        let categories = model.categories
        AppDialogFrame(title: shellString("chatManageCategories", "Manage category tags"), maxWidth: theme.sizes.dialogSm,
                       onClose: { model.showCategoryManager = false }) {
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                Text(categories.isEmpty ? shellString("chatNoCategories", "No tags yet. Right-click a chat and pick “Category…” to tag it.")
                                        : shellString("chatManageCategoriesHint", "Renaming or deleting a tag changes it on every chat it is on."))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx2).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(spacing: theme.spacing.s4) {
                        ForEach(categories, id: \.name) { c in CategoryRow(model: model, name: c.name) }
                    }
                }
                .frame(maxHeight: theme.sizes.dialogSm)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        } actions: {
            Spacer(minLength: 0)
            AppButton(appString("close", "Close"), kind: .ghost) { model.showCategoryManager = false }
        }
    }
}

private struct CategoryRow: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let name: String

    var body: some View {
        HStack(spacing: theme.spacing.s10) {
            Image(systemName: "tag.fill").font(.system(size: theme.sizes.icon16)).foregroundStyle(chatNameHue(name, theme))
            Text(name).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
            Spacer(minLength: 0)
            AppIconButton("pencil", help: shellString("chatRenameCategory", "Rename category")) { model.groupDialog = .renameCategory(name) }
            AppIconButton("trash", help: shellString("chatDeleteCategory", "Delete category")) { model.groupDialog = .deleteCategory(name) }
                .foregroundStyle(theme.colors.red)
        }
        .padding(.vertical, theme.spacing.s2)
    }
}
