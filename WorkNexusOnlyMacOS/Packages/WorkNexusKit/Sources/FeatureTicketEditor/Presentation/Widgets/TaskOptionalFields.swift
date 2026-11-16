import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/task_optional_fields.dart
/// The task fields beyond what a task needs - module, story, files, who to notify, keywords and colour - which the
/// form's simple mode leaves out.
struct TaskOptionalFields: View {
    @Environment(\.appTheme) private var theme
    let controller: TaskEditorController
    let state: TaskEditorState

    var body: some View {
        let draft = state.draft, options = state.form.options
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: theme.spacing.s14) {
                EditorField(label: appString("fieldModule", "Module")) {
                    OptionSelect(options: options.modules, value: draft.module, noneValue: "0") { v in controller.edit { $0.module = v } }
                }
                EditorField(label: appString("fieldStory", "Story")) {
                    OptionSelect(options: options.stories, value: draft.story, noneValue: "0") { v in controller.edit { $0.story = v } }
                }
            }
            EditorField(label: appString("attachments", "Attachments")) {
                AttachmentsInput(files: draft.files, newFiles: draft.newFiles,
                                 onFilesChanged: { v in controller.edit { $0.files = v } },
                                 onNewFilesChanged: { v in controller.edit { $0.newFiles = v } })
            }
            HStack(alignment: .top, spacing: theme.spacing.s14) {
                EditorField(label: appString("fieldMailto", "Notify")) {
                    OptionMultiSelect(title: appString("fieldMailto", "Notify"), options: options.users, values: draft.mailto) { v in controller.edit { $0.mailto = v } }
                }
                EditorField(label: appString("fieldKeywords", "Keywords")) {
                    EditorTextInput(initial: draft.keywords) { v in controller.edit { $0.keywords = v } }
                }
            }
            EditorField(label: appString("fieldColor", "Colour")) {
                TitleColorInput(value: draft.color) { v in controller.edit { $0.color = v } }
            }
        }
    }
}
