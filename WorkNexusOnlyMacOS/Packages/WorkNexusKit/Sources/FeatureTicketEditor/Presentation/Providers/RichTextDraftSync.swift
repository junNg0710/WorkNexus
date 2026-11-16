import CoreUI
import Foundation

/// Ported from: lib/features/ticket_editor/presentation/widgets/rich_text_draft_sync.dart
/// Hands a rich-text field (a bug's steps, a task's description) to the editor's draft once typing pauses. The
/// field keeps its own `RichDocument` in the `HtmlEditingController`, which is not observable, so a `Task` polls it
/// every `pause` and pushes the HTML when the document changed.
@MainActor
final class RichTextDraftSync {
    private let text: HtmlEditingController
    private let push: (String) -> Void
    private let pause: Duration
    private var last: RichDocument
    private var poller: Task<Void, Never>?

    init(_ text: HtmlEditingController, pause: Duration = .milliseconds(400), push: @escaping (String) -> Void) {
        self.text = text; self.push = push; self.pause = pause; last = text.document
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pause)
                self?.pushIfChanged()
            }
        }
    }

    private func pushIfChanged() {
        guard text.document != last else { return }
        last = text.document
        push(text.html)
    }

    /// Hands the text on now (before saving or closing).
    func pushNow() { last = text.document; push(text.html) }

    func stop() { poller?.cancel(); poller = nil }
}
