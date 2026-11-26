/// Not in the Flutter app.
import CoreDomain
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

    /// How many pictures one ticket takes along; the ones past it are quoted by their preview, as a file is.
    static let pictureLimit = 9

    /// The start of a ticket quoting `messages`. With `pictures` (a bug or a task, whose body can show them) the picture
    /// messages are fetched and taken along; one that cannot be fetched is quoted by its preview.
    @MainActor static func seed(_ messages: [ChatMessage], state: ChatThreadState, pictures repo: ChatRepository? = nil) async -> ChatTicketSeed {
        var lines: [DraftTicketFromMessages.Line] = [], taken: [ChatTicketPicture] = []
        let users = state.users
        for message in messages.sorted(by: { $0.sentAt < $1.sentAt }) {
            var quoted = line(message, users: users)
            if let repo, taken.count < pictureLimit, let picture = await picture(of: message, index: taken.count, repo) {
                quoted.pictureToken = picture.token
                taken.append(picture)
            }
            lines.append(quoted)
        }
        var seed = DraftTicketFromMessages()(lines, source: L.ticketSource(ChatShellLabels.title(state.chat, users)), clock: stamp)
        seed.pictures = taken
        return seed
    }

    /// The bytes of a picture message (not a sticker, which is a reaction); nil for any other message.
    private static func picture(of message: ChatMessage, index: Int, _ repo: ChatRepository) async -> ChatTicketPicture? {
        guard !message.deleted, case .image(let image) = message.content, !IsStickerImage()(image) else { return nil }
        let data: Data?
        if let inline = image.inlineBase64.flatMap({ Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }) {
            data = inline
        } else if image.fileId > 0 {
            data = await repo.loadAttachment(accountId: message.accountId, content: message.content, thumbnail: false).value
        } else {
            data = nil
        }
        guard let data, !data.isEmpty else { return nil }
        return ChatTicketPicture(token: ChatTicketPicture.token(index), name: image.name, data: data)
    }

    /// Several messages as one text, oldest first: "[time] Name: text".
    static func transcript(_ messages: [ChatMessage], users: [Int: ChatUser]) -> String {
        messages.sorted { $0.sentAt < $1.sentAt }.map { line($0, users: users) }
            .map { "[\(stamp($0.sentAt))] \($0.sender): \($0.text)" }.joined(separator: "\n")
    }

    static func stamp(_ date: Date) -> String {
        CachedDateFormatter.string(date, format: "yyyy-MM-dd HH:mm", locale: .current)
    }
}
