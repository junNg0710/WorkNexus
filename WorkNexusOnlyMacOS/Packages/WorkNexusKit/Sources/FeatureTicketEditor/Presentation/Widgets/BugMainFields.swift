import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/bug_main_fields.dart
/// The bug's text: title, repro steps (rich text) and files.
struct BugMainFields: View {
    let controller: BugEditorController
    let state: BugEditorState
    /// The steps as edited (read back into the draft on save).
    let steps: HtmlEditingController

    var body: some View {
        EditorSection(title: appString("editorSectionContent", "Content"), systemImage: "text.alignleft") {
            EditorField(label: appString("fieldTitle", "Title"), required: true, missing: state.missing.contains(.title)) {
                EditorTextInput(initial: state.draft.title, big: true) { v in controller.edit { $0.title = v } }
            }
            EditorField(label: appString("fieldSteps", "Repro steps")) {
                RichTextEditor(controller: steps, imageLoader: controller.imageLoader,
                               onUploadImage: { data, name in await controller.uploadImage(data, name) },
                               onDropFiles: { files in controller.edit { $0.newFiles += files.map { DraftFile(name: $0.name, bytes: $0.bytes) } } },
                               minHeight: 240)
            }
        }
        EditorSection(title: appString("attachments", "Attachments"), systemImage: "paperclip") {
            AttachmentsInput(files: state.draft.files, newFiles: state.draft.newFiles,
                             onFilesChanged: { v in controller.edit { $0.files = v } },
                             onNewFilesChanged: { v in controller.edit { $0.newFiles = v } })
        }
    }
}
