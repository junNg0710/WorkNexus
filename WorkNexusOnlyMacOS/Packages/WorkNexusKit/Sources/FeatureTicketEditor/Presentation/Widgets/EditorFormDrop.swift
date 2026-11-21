import CoreDomain
import CoreUI
import SwiftUI

/// Not in the Flutter app. Files dropped anywhere on a bug or task form, not only on the description or the attachments:
/// pictures go into the description (where its caret last was), the rest are attached. A picture that cannot be
/// uploaded is attached instead, so nothing dropped is lost.
struct EditorFormDrop: ViewModifier {
    let text: HtmlEditingController
    let upload: (Data, String) async -> String?
    let attach: ([DraftFile]) -> Void

    func body(content: Content) -> some View {
        FileDropTarget(hint: appString("dropFilesOnForm", "Drop images to put in the description, other files to attach"),
                       onDrop: drop) { content }
    }

    func drop(_ files: [DroppedFile]) async {
        let split = DroppedFiles.split(files)
        var attached = split.others.map { DraftFile(name: $0.name, bytes: $0.bytes) }
        for image in split.images {
            if let url = await upload(image.bytes, image.name) { text.insertImage(url) }
            else { attached.append(DraftFile(name: image.name, bytes: image.bytes)) }
        }
        if !attached.isEmpty { attach(attached) }
    }
}

extension View {
    /// Takes files dropped anywhere on the form (see `EditorFormDrop`).
    func editorFormDrop(text: HtmlEditingController, upload: @escaping (Data, String) async -> String?,
                        attach: @escaping ([DraftFile]) -> Void) -> some View {
        modifier(EditorFormDrop(text: text, upload: upload, attach: attach))
    }
}
