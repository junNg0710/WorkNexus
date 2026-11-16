/// Ported from: lib/tools/zentao/presentation/detail/zentao_task_action_dialog.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import UniformTypeIdentifiers

/// Runs a status action on a ZenTao task, asking what ZenTao's own form for it does: the hours worked and left, who it
/// goes to next, when work really began and ended, files and a note.
struct ZentaoTaskActionDialog: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let state: ZentaoUIState; let ticket: Ticket; let onClose: () -> Void
    @State private var form: ZentaoTaskActionForm
    @State private var note: ZentaoNoteModel
    @State private var busy = false

    init(deps: ZentaoDependencies, state: ZentaoUIState, ticket: Ticket, action: ZenTaoTaskAction, onClose: @escaping () -> Void) {
        self.deps = deps; self.state = state; self.ticket = ticket; self.onClose = onClose
        _form = State(initialValue: ZentaoTaskActionForm(ticket: ticket, action: action))
        _note = State(initialValue: ZentaoNoteModel(ticket: ticket))
    }

    private func submit(_ label: String) {
        busy = true
        let input = form.input(comment: note.value), t = ticket, wf = deps.workflow, action = form.action
        Task {
            await ZentaoActionRunner.run(state: state, ticket: t, toasts: toasts, label: label) { await wf.runTaskAction(t, action, input) }
            onClose()
        }
    }

    var body: some View {
        let action = form.action, look = ZentaoActionLooks.task(action), problem = form.problem
        ZentaoActionFrame(title: ZentaoActionLooks.title(look.label, ticket.externalKey), icon: look.icon, submitLabel: look.label,
                          busy: busy, canSubmit: problem == nil, onSubmit: { submit(look.label) }, onClose: onClose) {
            if action.asksSpent || action.asksLeft {
                if !form.hoursHint.isEmpty {
                    Text(form.hoursHint).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).padding(.bottom, theme.spacing.s12)
                }
                HStack(alignment: .top, spacing: theme.spacing.s12) {
                    if action.asksSpent { ZentaoTaskHoursField(label: appString("zentaoHoursSpent", "Hours worked this time"), text: $form.spent) }
                    if action.asksLeft { ZentaoTaskHoursField(label: appString("zentaoHoursLeft", "Hours left"), text: $form.left) }
                }
                if let problem, problem != .endBeforeBegin { ZentaoTaskProblemLine(problem) }
                ZentaoFieldGap()
            }
            if action.asksAssignee {
                ZentaoFieldLabel(appString("zentaoAssignToOptional", "Assign to (optional)"))
                ZentaoAssigneeDropdown(deps: deps, ticket: ticket, value: form.assignee) { form.assignee = $0 }
                ZentaoFieldGap()
            }
            if action.asksBegin || action.asksEnd {
                HStack(alignment: .top, spacing: theme.spacing.s12) {
                    if action.asksBegin {
                        ZentaoTaskDateField(label: appString("zentaoActualBegin", "Actual begin"), value: form.began, enabled: form.beginEditable) { form.began = $0 }
                    }
                    if action.asksEnd {
                        ZentaoTaskDateField(label: appString("zentaoActualEnd", "Actual end"), value: form.ended) { form.ended = $0 }
                    }
                }
                if problem == .endBeforeBegin { ZentaoTaskProblemLine(.endBeforeBegin) }
                ZentaoFieldGap()
            }
            if action.asksFiles {
                ZentaoFieldLabel(appString("zentaoFiles", "Files"))
                ZentaoFilesInput(files: $form.files)
                ZentaoFieldGap()
            }
            ZentaoFieldLabel(appString("zentaoNote", "Note"))
            ZentaoNoteField(deps: deps, ticket: ticket, note: note,
                            onDropFiles: action.asksFiles ? { dropped in form.files += dropped.map { DraftFile(name: $0.name, bytes: $0.bytes) } } : nil)
        }
    }
}

/// Files picked to attach with a task action (the Flutter `AttachmentsInput`, new files only).
struct ZentaoFilesInput: View {
    @Environment(\.appTheme) private var theme
    @Binding var files: [DraftFile]

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { if let data = try? Data(contentsOf: url) { files.append(DraftFile(name: url.lastPathComponent, bytes: data)) } }
    }

    var body: some View {
        FileDropTarget(hint: appString("dropFilesToAttach", "Drop files to attach"),
                       onDrop: { dropped in files += dropped.map { DraftFile(name: $0.name, bytes: $0.bytes) } }) {
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                ForEach(Array(files.enumerated()), id: \.offset) { i, f in
                    HStack(spacing: theme.spacing.s8) {
                        Image(systemName: "paperclip").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx3)
                        Text(f.name).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).lineLimit(1)
                        Text(formatFileSize(f.bytes.count) ?? "").font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
                        Spacer(minLength: 0)
                        AppIconButton("xmark", help: appString("chatRemoveAttachment", "Remove")) { files.remove(at: i) }
                    }
                }
                AppButton(appString("addFiles", "Add files"), systemImage: "plus", action: pick)
            }
            .padding(theme.spacing.s4)
        }
    }
}
