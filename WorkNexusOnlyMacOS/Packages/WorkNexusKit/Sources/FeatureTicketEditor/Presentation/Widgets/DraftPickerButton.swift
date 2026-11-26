import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/draft_picker_button.dart (+ util/ticket_draft_labels.dart)
/// "Drafts (n)" in a new bug's / task's editor: the other kept drafts of the same kind and account, newest first.
/// Each one can be opened (its launch goes to `onPick`) or deleted, and all of them deleted at once (asked first).
/// Hidden while there is none.
struct DraftPickerButton: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var all: [ZenTaoSavedDraft] = []
    @State private var confirmDeleteAll = false
    let repository: ZenTaoTicketDraftRepository
    let isBug: Bool
    let accountId: String
    /// The draft being edited, left out of the list.
    let currentDraftId: String?
    let onPick: (TicketEditorLaunch) -> Void

    private var drafts: [ZenTaoSavedDraft] {
        all.filter {
            guard $0.accountId == accountId, $0.id != currentDraftId else { return false }
            if case .bug = $0.content { return isBug }
            return !isBug
        }
    }

    var body: some View {
        Group {
            let list = drafts
            if !list.isEmpty {
                AppMenuButton(items: { menu(drafts) }) {
                    HStack(spacing: theme.spacing.s4) {
                        Label(appFormat("ticketDrafts", "Drafts (%1$@)", "\(list.count)"), systemImage: "doc.badge.clock")
                        Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12))
                    }
                    .font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                }
                .fixedSize()
            }
        }
        .task { for await drafts in repository.watchAll() { all = drafts } }
        .appConfirmDialog(isPresented: $confirmDeleteAll,
                          title: appFormat("ticketDraftsDeleteAllTitle", "Delete all %1$@ drafts?", "\(drafts.count)"),
                          message: appString("ticketDraftDiscardMessage", "What you wrote will be deleted."),
                          confirmLabel: appString("ticketDraftsDeleteAll", "Delete all drafts"), destructive: true) { delete(drafts) }
    }

    /// One row per draft (open it, or delete it), then "Delete all drafts…".
    private func menu(_ list: [ZenTaoSavedDraft]) -> [AppNativeMenu.Item] {
        list.map { d in
            AppNativeMenu.Item(Self.label(d), children: [
                AppNativeMenu.Item(appString("ticketDraftOpen", "Continue writing"), icon: "square.and.pencil") { onPick(.resuming(d)) },
                AppNativeMenu.Item(appString("ticketDraftDelete", "Delete draft"), icon: "trash", destructive: true) { delete([d]) },
            ])
        } + [AppNativeMenu.Item(appString("ticketDraftsDeleteAllAsk", "Delete all drafts…"), icon: "trash", destructive: true, dividerBefore: true) {
            confirmDeleteAll = true
        }]
    }

    /// Deletes `gone`; the first one that could not be deleted is told why.
    private func delete(_ gone: [ZenTaoSavedDraft]) {
        Task {
            for draft in gone {
                if case .failure(let f) = await repository.delete(id: draft.id) { toasts?.show(f.message); return }
            }
        }
    }

    /// `draft` as a menu row names it: its title (shortened) and when it was last changed.
    static func label(_ draft: ZenTaoSavedDraft) -> String {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return appFormat("ticketDraftLabel", "%1$@ · %2$@",
                         title.isEmpty ? appString("ticketDraftUntitled", "Untitled") : FormValueFormat.shortDraftTitle(title),
                         formatWhen(draft.updatedAt))
    }
}
