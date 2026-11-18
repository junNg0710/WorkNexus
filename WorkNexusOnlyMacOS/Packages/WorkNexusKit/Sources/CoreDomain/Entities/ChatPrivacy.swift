import Foundation

/// The chat's privacy mode, for a shared screen or a look over the shoulder: while `enabled`, the parts picked below are
/// hidden on screen until the pointer is on them. Only the display changes; nothing stored or sent does.
/// Ported from: lib/core/settings/chat_privacy.dart
public struct ChatPrivacy: Codable, Equatable, Hashable, Sendable {
    /// The master switch; also what the keyboard shortcut (⌘⇧H) flips.
    public var enabled = false
    /// The last message under each chat in the chat list: shown as dots.
    public var hidePreviews = true
    /// Chat names (shown as dots) and avatars (a plain placeholder), in the list, atop the open chat and in its composer hint.
    public var hideIdentities = true
    /// The messages of the open chat, of threads and pins: faded out, pictures covered in grey.
    public var hideMessages = true

    public init(enabled: Bool = false, hidePreviews: Bool = true, hideIdentities: Bool = true, hideMessages: Bool = true) {
        self.enabled = enabled; self.hidePreviews = hidePreviews; self.hideIdentities = hideIdentities; self.hideMessages = hideMessages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ChatPrivacy()
        enabled = c.value(.enabled, default: d.enabled)
        hidePreviews = c.value(.hidePreviews, default: d.hidePreviews)
        hideIdentities = c.value(.hideIdentities, default: d.hideIdentities)
        hideMessages = c.value(.hideMessages, default: d.hideMessages)
    }
}
