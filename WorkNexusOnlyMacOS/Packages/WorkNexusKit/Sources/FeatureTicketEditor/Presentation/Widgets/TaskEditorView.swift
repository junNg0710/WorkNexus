import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/task_editor_view.dart
/// Adds or edits a task, full screen; saving goes where the form's "After saving" choice says (by default it opens
/// the saved task).
struct TaskEditorView: View {
    @Environment(\.toasts) private var toasts
    @State private var controller: TaskEditorController
    @State private var confirmDiscard = false
    @State private var next: TaskAfterSave = .openTask
    let gateway: TicketEditorGateway
    let actions: EditorActions

    init(launch: TicketEditorLaunch, gateway: TicketEditorGateway, actions: EditorActions, prefill: TicketEditorPrefill? = nil) {
        _controller = State(initialValue: TaskEditorController(launch: launch, gateway: gateway, prefill: prefill))
        self.gateway = gateway; self.actions = actions
    }

    private var title: String {
        if case .editTask(_, let id) = controller.launch { return appFormat("editTaskTitle", "Edit task #%1$@", id) }
        return appString("newTask", "New task")
    }

    private func close() { Task { await controller.close(); actions.close() } }

    /// Saves, then goes where `next` says.
    private func save() {
        let after = next
        let execution = controller.state?.draft.execution ?? "0"
        Task {
            guard let ticketId = await controller.save() else { return }
            await controller.close()
            toasts?.show(appString("formSaved", "Saved"))
            switch after {
            case .openTask: actions.close(); actions.openTicket(ticketId)
            case .continueAdding: actions.startOver(.newTask(accountId: controller.launch.accountId, executionId: execution))
            case .backToList: actions.close()
            }
        }
    }

    private func discard() {
        Task {
            guard await controller.discardDraft() else { return }
            await controller.close()
            actions.close()
        }
    }

    private var picker: AnyView? {
        guard controller.launch.isNew, let drafts = gateway.drafts else { return nil }
        return AnyView(DraftPickerButton(repository: drafts, isBug: false, accountId: controller.launch.accountId,
                                         currentDraftId: controller.state?.draftId ?? controller.launch.draftId) { launch in
            Task { await controller.close(); actions.switchTo(launch) }
        })
    }

    var body: some View {
        let state = controller.state
        VStack(spacing: 0) {
            EditorHeader(title: title, kind: "task", onClose: close, onSave: state == nil ? nil : save, saving: state?.saving ?? false,
                         error: state?.failure?.message, draftSaved: state?.draftSavedAt != nil, draftPicker: picker,
                         onDiscardDraft: state?.draftSavedAt == nil ? nil : { confirmDiscard = true })
            if let state, let desc = controller.desc {
                TaskFormCentered(controller: controller, state: state, desc: desc, next: $next, onSave: save, onClose: close)
                    .editorFormDrop(text: desc, upload: { await controller.uploadImage($0, $1) },
                                    attach: { files in controller.edit { $0.newFiles += files } })
            } else {
                EditorLoadState(failure: controller.loadFailure) { Task { await controller.load() } }
            }
        }
        .editorShortcuts(onClose: close, onSave: state == nil || state?.saving == true ? nil : save)
        .appConfirmDialog(isPresented: $confirmDiscard, title: appString("ticketDraftDiscardTitle", "Discard this draft?"),
                          message: appString("ticketDraftDiscardMessage", "What you wrote will be deleted."),
                          confirmLabel: appString("ticketDraftDiscard", "Discard draft"), destructive: true, onConfirm: discard)
        .task { await controller.load() }
        // Closed from outside (another place, another draft picked from the "+" menu): what was typed last is kept too.
        .onDisappear { Task { await controller.close() } }
    }
}
