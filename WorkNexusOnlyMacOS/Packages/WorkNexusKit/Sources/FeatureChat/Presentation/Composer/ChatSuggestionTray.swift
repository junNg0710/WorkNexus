/// Ported from: lib/features/chat/presentation/widgets/chat_suggestion_tray.dart, chat_reply_suggestions_bar.dart,
/// chat_sticker_suggestions_bar.dart
import CoreUI
import SwiftUI

/// Suggestions over the composer's tools (AI replies, stickers): one header line — icon, label, close — with the suggestions
/// under the label. The icon sits in the column of the tool icons below, and a hairline sets the tray apart from them.
struct ChatSuggestionTray<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let systemImage: String
    let label: String
    var isError = false
    let closeHelp: String
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        // The tool buttons are control36 wide after the tools' s12 padding: centring the icon in that box puts it over theirs.
        let lead = theme.spacing.s12 + (theme.sizes.control36 - theme.sizes.icon16) / 2
        VStack(alignment: .leading, spacing: theme.spacing.s2) {
            HStack(spacing: theme.spacing.s8) {
                Image(systemName: systemImage).font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.accent)
                    .frame(width: theme.sizes.icon16)
                Text(label).font(theme.typography.caption).foregroundStyle(isError ? theme.colors.red : theme.colors.tx2).lineLimit(2)
                Spacer(minLength: 0)
                AppIconButton("xmark", help: closeHelp, action: onClose)
            }
            content.padding(.leading, theme.sizes.icon16 + theme.spacing.s8)
        }
        .padding(EdgeInsets(top: theme.spacing.s4, leading: lead, bottom: theme.spacing.s8, trailing: theme.spacing.s12))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}

/// Replies the AI suggested, in the tray. Picking one puts it in the input to edit before sending — never sends it.
struct ChatReplySuggestionsBar: View {
    @Environment(\.appTheme) private var theme
    let controller: ChatComposerController

    var body: some View {
        let phase = controller.ai.replies
        if phase != .idle {
            ChatSuggestionTray(systemImage: "sparkles", label: Self.label(phase), isError: Self.failed(phase),
                               closeHelp: appString("close", "Close"), onClose: { controller.ai.clearReplies() }) {
                if case .ready(let replies) = phase {
                    // Wrapped, not one clipped row: each reply has to be read whole.
                    FlowLayout(spacing: theme.spacing.s8) {
                        ForEach(replies, id: \.self) { reply in ReplyChip(reply: reply) { controller.pickReply(reply) } }
                    }
                }
            }
        }
    }

    private static func label(_ phase: ChatAiPhase<[String]>) -> String {
        switch phase {
        case .ready: appString("chatAiSuggestionHint", "Pick one to edit it before sending")
        case .failed(let reason): ChatComposerController.aiFailed(reason)
        default: appString("chatAiSuggesting", "Thinking of replies…")
        }
    }

    private static func failed(_ phase: ChatAiPhase<[String]>) -> Bool { if case .failed = phase { true } else { false } }
}

/// One suggested reply.
private struct ReplyChip: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let reply: String
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            Text(reply).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).multilineTextAlignment(.leading)
                .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s6)
                .background(hovering ? theme.colors.sel : theme.colors.panel2, in: Capsule())
                .overlay(Capsule().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

/// A strip of stickers in the tray, as messengers show: while typing, stickers for the words or emoji typed (one click sends
/// it, and clears the draft when the sticker says all of it); with nothing typed, stickers answering the newest message when
/// it is someone else's.
struct ChatStickerSuggestionsBar: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    let controller: ChatComposerController

    var body: some View {
        if let offer = controller.stickerSuggestions.offer(enabled: settings.stickerSuggestions) {
            ChatSuggestionTray(systemImage: "face.smiling",
                               label: offer.typing ? appString("chatStickerSuggestions", "Send as a sticker")
                                                   : appString("chatStickerReplies", "Reply with a sticker"),
                               closeHelp: appString("chatStickerSuggestionsClose", "Hide sticker suggestions"),
                               onClose: { controller.stickerSuggestions.close() }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacing.s8) {
                        ForEach(offer.stickers) { sticker in
                            SuggestedSticker(sticker: sticker) {
                                controller.sendSuggested(sticker, clearDraft: offer.typing && offer.replacesDraft)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One suggested sticker; a click sends it.
private struct SuggestedSticker: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let sticker: ChatSticker
    let onTap: () -> Void

    var body: some View {
        let side = theme.sizes.control36 * 1.5
        Button(action: onTap) {
            ChatStickerImage(sticker: sticker)
                .frame(width: side, height: side)
                .padding(theme.spacing.s2)
                .background(hovering ? theme.colors.panel2 : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.help(sticker.emoji)
    }
}
