import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/task_form_centered.dart
/// The centered, balanced two-column form for creating and editing tasks. Simple mode shows only what a task needs;
/// the optional fields keep their values and are still saved.
struct TaskFormCentered: View {
    @Environment(\.appTheme) private var theme
    @State private var simple = false
    let controller: TaskEditorController
    let state: TaskEditorState
    let desc: HtmlEditingController
    @Binding var next: TaskAfterSave
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        let draft = state.draft, options = state.form.options, missing = state.missing
        let isEditing = draft.id != nil
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(draft.id.map { appFormat("editTaskTitle", "Edit task #%1$@", $0) } ?? appString("newTask", "New task"))
                        .font(theme.typography.title).foregroundStyle(theme.colors.tx)
                    Spacer()
                    TaskFormModeToggle(isSimple: simple) { simple = $0 }
                }
                .padding(.bottom, theme.spacing.s10)
                Divider().overlay(theme.colors.line).padding(.bottom, theme.spacing.s20)

                HStack(alignment: .top, spacing: theme.spacing.s14) {
                    EditorField(label: appString("fieldExecution", "Execution"), required: true, missing: missing.contains(.execution)) {
                        OptionSelect(options: options.executions, value: draft.execution) { v in Task { await controller.changeExecution(v) } }
                    }
                    EditorField(label: appString("fieldTaskType", "Task type"), required: true, missing: missing.contains(.type)) {
                        OptionSelect(options: ZenTaoChoices.withValue(ZenTaoChoices.taskTypes, draft.type), value: draft.type) { v in controller.edit { $0.type = v } }
                    }
                }
                HStack(alignment: .top, spacing: theme.spacing.s14) {
                    if !simple {
                        EditorField(label: appString("parentTask", "Parent task")) {
                            OptionSelect(options: options.parents.filter { $0.value != draft.id }, value: draft.parent, noneValue: "0") { v in controller.edit { $0.parent = v } }
                        }
                    }
                    EditorField(label: appString("fieldAssignTo", "Assign to")) {
                        OptionSelect(options: options.users, value: draft.assignedTo, noneValue: "") { v in controller.edit { $0.assignedTo = v } }
                    }
                }
                EditorField(label: appString("fieldName", "Name"), required: true, missing: missing.contains(.name)) {
                    EditorTextInput(initial: draft.name, big: true) { v in controller.edit { $0.name = v } }
                }
                HStack(alignment: .top, spacing: theme.spacing.s14) {
                    EditorField(label: "\(appString("fieldEstStarted", "Start")) – \(appString("fieldDeadline", "Deadline"))",
                                missing: missing.contains(.deadline), missingText: appString("zentaoEndBeforeBegin", "The end can't be before the begin")) {
                        TaskTimeframeInput(estStarted: draft.estStarted, deadline: draft.deadline,
                                           onEstStartedChanged: { v in controller.edit { $0.estStarted = v } },
                                           onDeadlineChanged: { v in controller.edit { $0.deadline = v } })
                    }
                    EditorField(label: "\(appString("priority", "Priority")) · \(appString("fieldEstimate", "Estimate (h)"))") {
                        TaskPriorityEstimateInput(priority: draft.pri, estimate: draft.estimate,
                                                  onPriorityChanged: { v in controller.edit { $0.pri = v } },
                                                  onEstimateChanged: { v in controller.edit { $0.estimate = FormValueFormat.parseHours(v) } })
                    }
                }
                // An existing task's status and hours (ZenTao's edit form).
                if isEditing { TaskProgressFields(controller: controller, draft: draft) }
                EditorField(label: appString("description", "Description")) {
                    RichTextEditor(controller: desc, imageLoader: controller.imageLoader,
                                   onUploadImage: { data, name in await controller.uploadImage(data, name) },
                                   onDropFiles: { files in controller.edit { $0.newFiles += files.map { DraftFile(name: $0.name, bytes: $0.bytes) } } },
                                   minHeight: 200)
                }
                // Where saving a new task goes next.
                if !isEditing {
                    EditorField(label: appString("taskFormNext", "After saving")) { TaskNextActionSelector(action: next) { next = $0 } }
                }
                if !simple {
                    TaskOptionalFields(controller: controller, state: state)
                } else if !draft.files.isEmpty || !draft.newFiles.isEmpty {
                    // A file pasted or dropped in simple mode is attached all the same: it shows, so that is seen.
                    EditorField(label: appString("attachments", "Attachments")) {
                        AttachmentsInput(files: draft.files, newFiles: draft.newFiles,
                                         onFilesChanged: { v in controller.edit { $0.files = v } },
                                         onNewFilesChanged: { v in controller.edit { $0.newFiles = v } })
                    }
                }
                HStack(spacing: theme.spacing.s10) {
                    Spacer()
                    if state.saving { ProgressView().controlSize(.small) } else {
                        AppButton(appString("save", "Save"), kind: .primary, action: onSave)
                    }
                    AppButton(appString("back", "Back"), kind: .ghost, action: onClose)
                    Spacer()
                }
                .padding(.top, theme.spacing.s20)
            }
            .padding(theme.spacing.s24)
            .background(theme.colors.panel, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, theme.spacing.s20).padding(.vertical, theme.spacing.s14)
        }
    }
}
