/// Ported from: lib/features/chat/presentation/widgets/chat_image_body.dart, chat_file_body.dart (hand-off to the Media slice)
import SwiftUI

/// The single place the thread hands an image / file / video body to the Composer/Media slice (`ChatMediaBody`). Retarget
/// here if that view's name or shape changes.
struct MessageMediaAdapter: View {
    let message: ChatMessage
    let state: ChatThreadState

    var body: some View { ChatMediaBody(message: message, state: state) }
}
