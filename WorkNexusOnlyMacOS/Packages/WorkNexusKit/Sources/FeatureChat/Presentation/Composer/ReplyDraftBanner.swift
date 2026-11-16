/// Ported from: lib/features/chat/presentation/widgets/reply_draft_banner.dart
import CoreUI
import SwiftUI

/// Above the input while replying: who and what is answered, with a cancel button.
struct ReplyDraftBanner: View {
    @Environment(\.appTheme) private var theme
    let message: ChatMessage
    let state: ChatThreadState
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            RoundedRectangle(cornerRadius: theme.radii.xs).fill(theme.colors.accent).frame(width: theme.borders.thick)
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text("\(appString("chatReplyingTo", "Replying to")) \(senderName)")
                    .font(theme.typography.label).foregroundStyle(theme.colors.accent).lineLimit(1)
                Text(preview).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).lineLimit(1)
            }
            Spacer(minLength: 0)
            AppIconButton("xmark", help: appString("chatCancelReply", "Cancel reply"), action: onCancel)
        }
        .frame(height: theme.sizes.control36 + theme.spacing.s4)
        .padding(.horizontal, theme.spacing.s12)
        .padding(.top, theme.spacing.s8)
    }

    private var senderName: String {
        if message.isMine { return appString("chatYou", "You") }
        if let u = state.users[message.senderId] { return u.realname.isEmpty ? u.account : u.realname }
        return appString("chatUnknownUser", "User #{id}").replacingOccurrences(of: "{id}", with: "\(message.senderId)")
    }

    private var preview: String {
        switch message.content {
        case .text(let t, _): return DecodeEmoji()(Mentions.repair(t)).replacingOccurrences(of: #"\[@([^\]]+)\]\(@#\d+\)"#, with: "@$1", options: .regularExpression)
        case .image: return appString("chatImage", "Image")
        case .file(let f): return f.name
        case .emoji(let e): return DecodeEmoji()(e)
        case .code: return appString("chatCode", "Code")
        case .link(let url, let title): return title ?? url
        case .notification(let n): return n.title ?? n.text
        case .unsupported(let t): return appString("chatUnsupportedMessage", "Unsupported message ({type})").replacingOccurrences(of: "{type}", with: t)
        }
    }
}
