import Foundation

/// How the AI rewrites a message the user is typing.
/// Ported from: lib/features/chat/domain/value_objects/chat_draft_tone.dart
public enum ChatDraftTone: String, CaseIterable, Sendable {
    /// Fixes grammar and spelling and makes it easy to follow.
    case clearer
    /// Polite and professional.
    case formal
    /// Warm and friendly.
    case friendly
    /// To the point.
    case shorter
}
