import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/draft_picker_button.dart (+ util/ticket_draft_labels.dart)
/// "Drafts (n)" in a new bug's / task's editor: the other kept drafts of the same kind and account, newest first;
/// picking one hands its launch to `onPick`. Hidden while there is none.
struct DraftPickerButton: View {
    @Environment(\.appTheme) private var theme
    @State private var all: [ZenTaoSavedDraft] = []
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
                Menu {
                    ForEach(list) { d in Button(Self.label(d)) { onPick(.resuming(d)) } }
                } label: {
                    Label(appFormat("ticketDrafts", "Drafts (%1$@)", "\(list.count)"), systemImage: "doc.badge.clock")
                        .font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
        .task { for await drafts in repository.watchAll() { all = drafts } }
    }

    /// `draft` as a menu row names it: its title (shortened) and when it was last changed.
    static func label(_ draft: ZenTaoSavedDraft) -> String {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return appFormat("ticketDraftLabel", "%1$@ · %2$@",
                         title.isEmpty ? appString("ticketDraftUntitled", "Untitled") : FormValueFormat.shortDraftTitle(title),
                         formatWhen(draft.updatedAt))
    }
}
