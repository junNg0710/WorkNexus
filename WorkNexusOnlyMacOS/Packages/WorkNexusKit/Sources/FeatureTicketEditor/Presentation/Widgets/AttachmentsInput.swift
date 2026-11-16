import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import UniformTypeIdentifiers

/// Ported from: lib/core/widgets/attachments_input.dart
/// The files on the bug or task - those already there (`files`, removable) and those picked to attach when it is
/// saved (`newFiles`) - with an "add files" button (or drop files on it).
struct AttachmentsInput: View {
    @Environment(\.appTheme) private var theme
    let files: [TicketAttachment]
    let newFiles: [DraftFile]
    let onFilesChanged: ([TicketAttachment]) -> Void
    let onNewFilesChanged: ([DraftFile]) -> Void

    var body: some View {
        FileDropTarget(hint: appString("dropFilesToAttach", "Drop files to attach"),
                       onDrop: { dropped in onNewFilesChanged(newFiles + dropped.map { DraftFile(name: $0.name, bytes: $0.bytes) }) }) {
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                if !files.isEmpty || !newFiles.isEmpty {
                    FlowLayout(spacing: theme.spacing.s6) {
                        ForEach(files) { f in
                            EditorChip(label: f.title, systemImage: "paperclip") { onFilesChanged(files.filter { $0.id != f.id }) }
                        }
                        ForEach(Array(newFiles.enumerated()), id: \.offset) { i, f in
                            EditorChip(label: f.name, systemImage: "plus.circle") {
                                var left = newFiles; left.remove(at: i); onNewFilesChanged(left)
                            }
                        }
                    }
                }
                AppButton(appString("addFiles", "Add files"), systemImage: "paperclip", action: pick)
            }
            .padding(theme.spacing.s4)
        }
        .padding(.bottom, theme.spacing.s14)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { add(panel.urls) }
    }

    private func add(_ urls: [URL]) {
        let added = urls.compactMap { url in (try? Data(contentsOf: url)).map { DraftFile(name: url.lastPathComponent, bytes: $0) } }
        if !added.isEmpty { onNewFilesChanged(newFiles + added) }
    }
}
