import Foundation

/// A new chat message, as the pet tells it: the chat, who wrote (in a group) and a line of what they wrote. `number`
/// counts them, so the same words twice are still news. Not in the Flutter app.
public struct PetChatNews: Equatable, Sendable {
    /// The chat's name (the sender's, in a direct chat).
    public var title: String
    /// Who wrote, in a group chat; nil in a direct chat.
    public var sender: String?
    /// One line of the message ("Photo", "File: spec.pdf", the text...).
    public var body: String
    public var number: Int
}
