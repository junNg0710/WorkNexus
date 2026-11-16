/// Not in the Flutter app.
import Foundation

/// A message taken out of the chat as text: copied, or quoted in a ticket.
enum ChatMessageExport {
    /// The text "Copy" puts on the clipboard: the words of a text message (mentions as `@name`), the code of a snippet.
    static func text(of message: ChatMessage) -> String? {
        if message.deleted { return nil }
        if case .code(let code, _, _) = message.content { return code }
        return message.content.asText.map { ChatTextLabels.copyText($0.text) }
    }

    /// The message as a ticket or a transcript quotes it; one without text (a picture, a file) by its one-line preview.
    static func line(_ message: ChatMessage, users: [Int: ChatUser]) -> DraftTicketFromMessages.Line {
        DraftTicketFromMessages.Line(sender: ChatTextLabels.userName(users, message.senderId), sentAt: message.sentAt,
                                     text: text(of: message) ?? ChatTextLabels.preview(message))
    }

    @MainActor static func seed(_ messages: [ChatMessage], state: ChatThreadState) -> ChatTicketSeed {
        DraftTicketFromMessages()(messages.map { line($0, users: state.users) },
                                  source: L.ticketSource(ChatShellLabels.title(state.chat, state.users)), clock: stamp)
    }

    /// Several messages as one text, oldest first: "[time] Name: text".
    static func transcript(_ messages: [ChatMessage], users: [Int: ChatUser]) -> String {
        messages.sorted { $0.sentAt < $1.sentAt }.map { line($0, users: users) }
            .map { "[\(stamp($0.sentAt))] \($0.sender): \($0.text)" }.joined(separator: "\n")
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}
