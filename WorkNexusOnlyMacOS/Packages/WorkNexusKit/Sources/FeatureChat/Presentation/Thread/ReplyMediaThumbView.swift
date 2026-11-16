/// Ported from: lib/features/chat/presentation/widgets/reply_media_thumb.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// The small square beside a quoted message (reply quote, reply draft) when it carries media: an image's thumbnail, a
/// video's preview frame with a play glyph, or a file's extension. Nothing for other content.
struct ReplyMediaThumbView: View {
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let content: MessageContent
    @State private var image: NSImage?

    static let side: CGFloat = 40

    /// Whether `content` gets a thumb, so callers can skip the gap beside it.
    static func shows(_ content: MessageContent) -> Bool {
        switch content { case .image, .file: true; default: false }
    }

    var body: some View {
        let radius = RoundedRectangle(cornerRadius: theme.radii.sm)
        if case .file(let f) = content, !isVideoFile(f) {
            Text(ChatTextLabels.fileBadge(f.name)).font(theme.typography.label).foregroundStyle(theme.colors.accentTx).lineLimit(1)
                .frame(width: Self.side, height: Self.side).background(theme.colors.accent, in: radius)
        } else if Self.shows(content) {
            ZStack {
                theme.colors.skel
                if let image { Image(nsImage: image).resizable().scaledToFill() }
                if case .file = content { Image(systemName: "play.circle").font(.system(size: theme.sizes.icon20)).foregroundStyle(theme.colors.onScrim) }
            }
            .frame(width: Self.side, height: Self.side).clipShape(radius)
            .task(id: content) { await load() }
        }
    }

    private func load() async {
        let chat = ctx.services.chat, account = ctx.accountId
        let bytes: Data?
        switch content {
        case .image: bytes = await LoadChatAttachment(chat)(accountId: account, content: content, thumbnail: true).value
        default: bytes = await LoadVideoThumbnail(chat)(accountId: account, video: content).value
        }
        image = bytes.flatMap(NSImage.init(data:))
    }
}
