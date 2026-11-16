/// Ported from: lib/features/chat/presentation/widgets/message_bubble_content.dart (media branches)
import CoreUI
import SwiftUI

/// The body of a message that carries media: an image or sticker, a file, a video, a large emoji or a code snippet. Switches on
/// `message.content`; other contents draw nothing.
public struct ChatMediaBody: View {
    let message: ChatMessage
    let state: ChatThreadState

    public init(message: ChatMessage, state: ChatThreadState) { self.message = message; self.state = state }

    public var body: some View {
        switch message.content {
        case .image(let image): ChatImageBody(message: message, image: image, state: state)
        case .file(let file):
            if isVideoFile(file) { ChatVideoTile(message: message, file: file, state: state) }
            else { ChatFileBody(message: message, file: file) }
        case .emoji(let code): ChatLargeEmoji(code: code)
        case .code(let code, let language, let name): ChatCodeBody(code: code, language: language, name: name)
        default: EmptyView()
        }
    }
}

/// An emoji sent large, without a bubble.
struct ChatLargeEmoji: View {
    let code: String
    var body: some View { Text(DecodeEmoji()(code)).font(.system(size: 56)).fixedSize() }
}
