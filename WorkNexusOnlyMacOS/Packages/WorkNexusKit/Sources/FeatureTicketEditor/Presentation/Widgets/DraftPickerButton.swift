import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/draft_picker_button.dart (+ util/ticket_draft_labels.dart)
/// "Drafts (n)" in a new bug's / task's editor: the other kept drafts of the same kind and account, newest first.
/// Each one can be opened (its launch goes to `onPick`) or discarded, and all of them deleted at once (asked first).
/// Hidden while there is none.
struct DraftPickerButton: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var kept = KeptTicketDrafts()
    @State private var confirmDeleteAll = false
    let repository: ZenTaoTicketDraftRepository
    let isBug: Bool
    let accountId: String
    /// The draft being edited, left out of the list.
    let currentDraftId: String?
    let onPick: (TicketEditorLaunch) -> Void

    private var drafts: [ZenTaoSavedDraft] {
        kept.drafts(accountId: accountId, isBug: isBug).filter { $0.id != currentDraftId }
    }

    var body: some View {
        // A stack, not a `Group`: with nothing in it a group is no view at all, and the task that reads the drafts never
        // ran - so the button never came up.
        HStack(spacing: 0) {
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
        .task { await kept.run(repository) }
        .appConfirmDialog(isPresented: $confirmDeleteAll,
                          title: appFormat("ticketDraftsDeleteAllTitle", "Delete all %1$@ drafts?", "\(drafts.count)"),
                          message: appString("ticketDraftDiscardMessage", "What you wrote will be deleted."),
                          confirmLabel: appString("ticketDraftsDeleteAll", "Delete all drafts"), destructive: true) { delete(drafts) }
    }

    private func menu(_ list: [ZenTaoSavedDraft]) -> [AppNativeMenu.Item] {
        TicketDraftMenu.items(list, open: { onPick(.resuming($0)) }, discard: { delete([$0]) }, discardAll: { confirmDeleteAll = true })
    }

    private func delete(_ gone: [ZenTaoSavedDraft]) {
        Task { if let f = await KeptTicketDrafts.discard(gone, from: repository) { toasts?.show(f.message) } }
    }
}
