import Foundation

/// Something a person in the chat is to do, as the AI read it: `owner` is empty when the messages name no one, `due` when
/// they set no deadline.
/// Ported from: lib/features/chat/domain/entities/chat_summary.dart
public struct ChatActionItem: Hashable, Sendable {
    public var task: String
    public var owner: String
    public var due: String
    public init(task: String, owner: String = "", due: String = "") { self.task = task; self.owner = owner; self.due = due }
}

/// An AI summary of a stretch of a chat, for catching up on it: what it is about (`overview`), the main points, what was
/// decided, who is to do what and what is still unanswered.
/// Ported from: lib/features/chat/domain/entities/chat_summary.dart
public struct ChatSummary: Hashable, Sendable {
    public var overview: String
    public var keyPoints: [String]
    public var decisions: [String]
    public var actionItems: [ChatActionItem]
    public var openQuestions: [String]
    /// How many messages were summarized.
    public var messageCount: Int
    /// The model that wrote it; nil when the backend did not say.
    public var model: String?

    public init(overview: String, keyPoints: [String] = [], decisions: [String] = [], actionItems: [ChatActionItem] = [],
                openQuestions: [String] = [], messageCount: Int, model: String? = nil) {
        self.overview = overview; self.keyPoints = keyPoints; self.decisions = decisions; self.actionItems = actionItems
        self.openQuestions = openQuestions; self.messageCount = messageCount; self.model = model
    }
}
