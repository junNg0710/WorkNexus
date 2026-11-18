import Foundation

/// A part of the chat UI the privacy mode can hide.
/// Ported from: lib/features/chat/domain/value_objects/chat_privacy_part.dart
public enum ChatPrivacyPart: String, CaseIterable, Hashable, Sendable {
    /// The last message under each chat in the chat list.
    case preview
    /// A chat's name and avatar (and the details that name a person: account, contacts, owner).
    case identity
    /// A message: its words fade, its pictures are covered.
    case message
}
