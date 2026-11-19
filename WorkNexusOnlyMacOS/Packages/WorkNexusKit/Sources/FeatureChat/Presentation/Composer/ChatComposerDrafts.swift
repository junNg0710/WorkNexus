/// Ported from: lib/features/chat/presentation/providers/chat_composer_draft_provider.dart (+ the staged files staying with
/// their chat, chat_staged_files_provider.dart)
import Foundation

/// What a composer held when it went away: the text with its mentions and caret, and the files waiting above it.
struct ChatComposerDraft: Equatable {
    var text: String
    var mentions: [ChatTextMention]
    var selection: NSRange
    var staged: [StagedFile]

    var isEmpty: Bool { text.isEmpty && staged.isEmpty }
}

/// Each composer's unsent draft, for as long as the app runs. The chat pane is built anew for every chat opened, so what was
/// typed (or pasted / dropped and not sent yet) was lost on switching to another chat and back. Keyed by account, chat and,
/// for a reply thread's composer, its root.
@MainActor
final class ChatComposerDrafts {
    static let shared = ChatComposerDrafts()
    private var drafts: [String: ChatComposerDraft] = [:]

    static func key(accountId: String, chatGid: String, threadRootId: Int?) -> String {
        "\(accountId)|\(chatGid)|\(threadRootId.map(String.init) ?? "-")"
    }

    func draft(_ key: String) -> ChatComposerDraft? { drafts[key] }

    /// Keeps `draft` for `key`; an empty one is forgotten.
    func save(_ draft: ChatComposerDraft, for key: String) {
        drafts[key] = draft.isEmpty ? nil : draft
    }
}
