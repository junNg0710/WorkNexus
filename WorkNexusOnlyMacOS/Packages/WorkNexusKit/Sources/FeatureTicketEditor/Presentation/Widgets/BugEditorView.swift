import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/bug_editor_view.dart
/// Adds or edits a bug, full screen; saving opens the saved bug.
struct BugEditorView: View {
    @Environment(\.toasts) private var toasts
    @State private var controller: BugEditorController
    @State private var confirmDiscard = false
    let gateway: TicketEditorGateway
    let actions: EditorActions

    init(launch: TicketEditorLaunch, gateway: TicketEditorGateway, actions: EditorActions) {
        _controller = State(initialValue: BugEditorController(launch: launch, gateway: gateway))
        self.gateway = gateway; self.actions = actions
    }

    private var title: String {
        if case .editBug(_, let id) = controller.launch { return appFormat("editBugTitle", "Edit bug #%1$@", id) }
        return appString("newBug", "New bug")
    }

    private func close() {
        // The draft keeps what was typed last.
        Task { await controller.close(); actions.close() }
    }

    private func save() {
        Task {
            guard let ticketId = await controller.save() else { return }
            await controller.close()
            actions.close()
            actions.openTicket(ticketId)
            toasts?.show(appString("formSaved", "Saved"))
        }
    }

    private func discard() {
        Task {
            // Not deleted: the editor stays open, the header saying why.
            guard await controller.discardDraft() else { return }
            await controller.close()
            actions.close()
        }
    }

    private var picker: AnyView? {
        guard controller.launch.isNew, let drafts = gateway.drafts else { return nil }
        return AnyView(DraftPickerButton(repository: drafts, isBug: true, accountId: controller.launch.accountId,
                                         currentDraftId: controller.state?.draftId ?? controller.launch.draftId) { launch in
            Task { await controller.close(); actions.switchTo(launch) }
        })
    }

    var body: some View {
        let state = controller.state
        VStack(spacing: 0) {
            EditorHeader(title: title, kind: "bug", onClose: close, onSave: state == nil ? nil : save, saving: state?.saving ?? false,
                         error: state?.failure?.message, draftSaved: state?.draftSavedAt != nil, draftPicker: picker,
                         onDiscardDraft: state?.draftSavedAt == nil ? nil : { confirmDiscard = true })
            if let state, let steps = controller.steps {
                EditorColumns {
                    BugMainFields(controller: controller, state: state, steps: steps)
                } side: {
                    BugSideFields(controller: controller, state: state)
                }
            } else {
                EditorLoadState(failure: controller.loadFailure) { Task { await controller.load() } }
            }
        }
        .editorShortcuts(onClose: close, onSave: state == nil || state?.saving == true ? nil : save)
        .appConfirmDialog(isPresented: $confirmDiscard, title: appString("ticketDraftDiscardTitle", "Discard this draft?"),
                          message: appString("ticketDraftDiscardMessage", "What you wrote will be deleted."),
                          confirmLabel: appString("ticketDraftDiscard", "Discard draft"), destructive: true, onConfirm: discard)
        .task { await controller.load() }
    }
}
