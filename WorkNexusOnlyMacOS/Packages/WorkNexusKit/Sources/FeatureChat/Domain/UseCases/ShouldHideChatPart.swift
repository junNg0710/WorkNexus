import CoreDomain
import Foundation

/// Whether `ChatPrivacy` hides a `ChatPrivacyPart` right now: only while the privacy mode is on, and only the parts the user
/// picked.
/// Ported from: lib/features/chat/domain/usecases/should_hide_chat_part.dart
public struct ShouldHideChatPart: Sendable {
    public init() {}

    public func callAsFunction(_ privacy: ChatPrivacy, _ part: ChatPrivacyPart) -> Bool {
        guard privacy.enabled else { return false }
        switch part {
        case .preview: return privacy.hidePreviews
        case .identity: return privacy.hideIdentities
        case .message: return privacy.hideMessages
        }
    }

    /// Every part hidden right now (empty while the mode is off): what the chat views read, once, from the environment.
    public func hiddenParts(_ privacy: ChatPrivacy) -> Set<ChatPrivacyPart> {
        Set(ChatPrivacyPart.allCases.filter { callAsFunction(privacy, $0) })
    }
}

/// Whether `content` draws as a picture (an image or sticker, a video, a big emoji): the privacy mode covers it in grey
/// rather than fading it, and the words around it fade on their own.
/// Ported from: lib/features/chat/presentation/widgets/message_body.dart (`isChatPicture`)
public func isChatPicture(_ content: MessageContent) -> Bool {
    switch content {
    case .image, .emoji: true
    case .file(let file): isVideoFile(file)
    default: false
    }
}

/// Whether a chat's subtitle names the person (their `@account`) rather than saying a count or a status: the privacy mode
/// hides it with the chat's name.
/// Ported from: lib/features/chat/presentation/widgets/chat_info_panel.dart, chat_thread_header.dart (subtitle masks)
public func chatSubtitleNamesPeer(_ subtitle: String, peerAccount: String?) -> Bool {
    subtitle.hasPrefix("@") || (peerAccount.map { !$0.isEmpty && subtitle == $0 } ?? false)
}
