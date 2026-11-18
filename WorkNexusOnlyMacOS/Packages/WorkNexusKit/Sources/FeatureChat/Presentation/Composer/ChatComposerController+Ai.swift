/// Ported from: lib/features/chat/presentation/widgets/chat_ai_compose_button.dart (`_suggest`, `_rewrite`),
/// chat_reply_suggestions_bar.dart (picking a reply) and chat_sticker_suggestions_bar.dart (`_send`)
import CoreDomain
import CoreUI
import Foundation

/// What the composer's ✨ menu and its suggestion trays do.
extension ChatComposerController {
    /// The AI help is offered: the host wired a backend.
    var offersAi: Bool { services?.ai != nil }

    private var aiContext: ChatAiContext? { services.map { ChatAiContext(services: $0, settings: settings, state: state) } }

    /// Asks the AI for replies to the latest messages (shown in the tray above the tools).
    func suggestReplies() {
        guard let context = aiContext else { return }
        let ai = ai
        Task { await ai.suggest(context) }
    }

    /// A suggested reply goes into the input to edit before sending — never sent as is.
    func pickReply(_ reply: String) {
        model.clear()
        model.insertText(reply)
        ai.clearReplies()
        model.requestFocus()
    }

    /// Rewrites what is typed in `tone`. Typing meanwhile wins: the answer replaces the draft only while it is still what was
    /// sent.
    func rewrite(_ tone: ChatDraftTone) {
        guard let context = aiContext else { return }
        if model.hasMentions {
            error = appString("chatAiRewriteNoMentions", "Rewriting would drop the @mentions in this message")
            return
        }
        let draft = model.plainText
        guard !model.isBlank else {
            error = appString("chatAiRewriteNeedsDraft", "Type a message for the AI to rewrite")
            return
        }
        let ai = ai
        Task {
            switch await ai.rewrite(draft, tone: tone, context: context) {
            case .success(let text)? where model.plainText == draft:
                model.clear()
                model.insertText(text)
                model.requestFocus()
            case .failure(let f)?: error = Self.aiFailed(f.message)
            default: break
            }
        }
    }

    static func aiFailed(_ reason: String) -> String {
        appFormat("chatAiFailed", "The AI couldn't answer: %1$@", reason)
    }

    /// The ✨ menu's switch for the sticker strip (saved by the host).
    func setStickerSuggestions(_ on: Bool) { services?.setStickerSuggestions?(on) }

    /// Sends a suggested sticker (answering the reply being written, else the thread root); it clears the draft when it says
    /// all of it.
    func sendSuggested(_ sticker: ChatSticker, clearDraft: Bool) {
        guard let sender else { return }
        if clearDraft {
            model.clear(); mentions.reset()
            stickerSuggestions.cleared()
        }
        model.requestFocus()
        Task { report(await sender.sticker(sticker)) }
    }
}
